const OpenAI = require('openai');
const { createRateLimitMiddleware } = require('./utils/rateLimiter');
const { Validator } = require('./utils/validator');
const {
  handleCORS,
  createAuthMiddleware,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

// Circuit breaker for OpenAI API
const openAIBreaker = new CircuitBreaker(5, 30000); // 5 failures, 30 second timeout

const SYSTEM_PROMPT = `You are a helpful AI assistant for TabletNotes, specializing in helping users understand and engage with sermon content.

STRICT GUIDELINES:
1. ONLY answer questions directly related to:
   - The sermon content (transcript/summary provided)
   - Biblical topics and theology
   - Christian faith and spiritual growth
   - Scripture interpretation and application

2. If asked about unrelated topics (politics, current events, entertainment, etc.), politely redirect:
   "I'm designed to help with sermon content and biblical questions. Could you ask something related to this sermon or a biblical topic?"

3. Provide thoughtful, biblically-grounded responses
4. Reference specific parts of the sermon when applicable
5. Be concise but comprehensive
6. Maintain a respectful, pastoral tone

You have access to:
- Sermon title, date, speaker, service type
- Full transcript (if available)
- AI-generated summary (if available)`;

exports.handler = withLogging('chat', async (event, context) => {
  const logger = event.logger;

  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  // Validate request size
  const sizeValidation = Validator.validateRequestSize(event);
  if (!sizeValidation.valid) {
    logger.warn('Request size validation failed', { error: sizeValidation.error });
    return createErrorResponse(new Error(sizeValidation.error), 413);
  }

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  // Apply rate limiting
  const rateLimitMiddleware = createRateLimitMiddleware('chat');
  const rateLimitResponse = await rateLimitMiddleware(event, context);
  if (rateLimitResponse) {
    logger.rateLimit(event.user?.id || 'anonymous', 'chat', false, {
      statusCode: rateLimitResponse.statusCode
    });
    return rateLimitResponse;
  }

  // Apply authentication
  const authMiddleware = createAuthMiddleware();
  const authResponse = await authMiddleware(event);
  if (authResponse) {
    logger.security('authentication_failed', {
      reason: 'missing_or_invalid_token',
      ip: event.headers['x-forwarded-for']
    });
    return authResponse;
  }

  try {
    const user = event.user;
    logger.info('User authenticated successfully', { userId: user.id });

    const body = JSON.parse(event.body || '{}');

    // Handle question generation
    if (body.action === 'generateQuestions') {
      logger.info('Generating suggested questions', { userId: user.id });

      const contextText = buildContextText(body.context);
      const count = body.count || 3;

      const openai = new OpenAI({
        apiKey: process.env.OPENAI_API_KEY,
      });

      // Use circuit breaker for OpenAI call
      const response = await openAIBreaker.execute(async () => {
        return await openai.chat.completions.create({
          model: 'gpt-4',
          messages: [
            {
              role: 'system',
              content: `Generate ${count} thought-provoking questions about this sermon that would help someone reflect deeper on the content. Return ONLY a JSON object with a "questions" array containing exactly ${count} question strings. No additional text or formatting.`,
            },
            {
              role: 'user',
              content: `Sermon context:\n${contextText}\n\nGenerate ${count} questions.`,
            },
          ],
          temperature: 0.7,
          max_tokens: 500,
          response_format: { type: 'json_object' },
        });
      });

      const questionsData = JSON.parse(response.choices[0].message.content || '{"questions":[]}');
      const questions = questionsData.questions || [];

      logger.info('Generated questions successfully', {
        userId: user.id,
        questionCount: questions.length
      });

      return createSuccessResponse({ questions });
    }

    // Handle chat message
    if (!body.message) {
      return createErrorResponse(new Error('Message is required'), 400);
    }

    logger.info('Processing chat message', {
      userId: user.id,
      messageLength: body.message.length,
      hasConversationHistory: !!body.conversationHistory
    });

    // Build context
    const contextText = buildContextText(body.context);

    // Build messages for OpenAI
    const messages = [
      {
        role: 'system',
        content: `${SYSTEM_PROMPT}\n\nCurrent sermon context:\n${contextText}`,
      },
    ];

    // Add conversation history
    if (body.conversationHistory && body.conversationHistory.length > 0) {
      // Limit to last 10 messages to avoid token overflow
      const recentHistory = body.conversationHistory.slice(-10);
      messages.push(...recentHistory.map(msg => ({
        role: msg.role,
        content: msg.content,
      })));
    }

    // Add current message
    messages.push({
      role: 'user',
      content: body.message,
    });

    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    // Call OpenAI with circuit breaker
    const response = await openAIBreaker.execute(async () => {
      return await openai.chat.completions.create({
        model: 'gpt-4',
        messages,
        temperature: 0.7,
        max_tokens: 1000,
      });
    });

    const aiResponse = response.choices[0].message.content;

    logger.info('Chat response generated successfully', {
      userId: user.id,
      responseLength: aiResponse.length
    });

    return createSuccessResponse({ response: aiResponse });
  } catch (error) {
    logger.error('Chat error', {
      error: error.message,
      stack: error.stack,
      userId: event.user?.id
    });

    // Handle specific error types
    if (error.code === 'insufficient_quota') {
      return createErrorResponse(new Error('OpenAI API quota exceeded'), 503);
    }

    if (error.code === 'rate_limit_exceeded') {
      return createErrorResponse(new Error('Rate limit exceeded, please try again later'), 429);
    }

    return createErrorResponse(error, 500);
  }
});

function buildContextText(context) {
  if (!context) {
    return 'No context available';
  }

  let text = `Title: ${context.title || 'Unknown'}\n`;
  text += `Service Type: ${context.serviceType || 'Unknown'}\n`;
  text += `Date: ${context.date || 'Unknown'}\n`;

  if (context.speaker) {
    text += `Speaker: ${context.speaker}\n`;
  }

  if (context.summary) {
    text += `\nSummary:\n${context.summary}\n`;
  }

  if (context.transcript) {
    text += `\nTranscript:\n${context.transcript}\n`;
  }

  return text;
}
