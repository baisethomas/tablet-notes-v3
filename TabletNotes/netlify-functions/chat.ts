// This file should be deployed to your Netlify functions folder
// Path: netlify/functions/chat.ts

import { Handler } from '@netlify/functions';
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

interface ChatRequest {
  message?: string;
  context: {
    title: string;
    serviceType: string;
    date: string;
    speaker?: string;
    summary?: string;
    transcript?: string;
  };
  conversationHistory?: Array<{ role: string; content: string }>;
  action?: 'generateQuestions';
  count?: number;
}

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

export const handler: Handler = async (event) => {
  // CORS headers
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  // Handle preflight
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 200, headers, body: '' };
  }

  // Verify auth token
  const authHeader = event.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return {
      statusCode: 401,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Unauthorized',
      }),
    };
  }

  try {
    const body: ChatRequest = JSON.parse(event.body || '{}');

    // Handle question generation
    if (body.action === 'generateQuestions') {
      const contextText = buildContextText(body.context);
      const count = body.count || 3;

      const response = await openai.chat.completions.create({
        model: 'gpt-4',
        messages: [
          {
            role: 'system',
            content: `Generate ${count} thought-provoking questions about this sermon that would help someone reflect deeper on the content. Return the questions as a JSON object with a "questions" array.`,
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

      const questionsData = JSON.parse(response.choices[0].message.content || '{}');
      const questions = questionsData.questions || [];

      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: true,
          data: { questions },
        }),
      };
    }

    // Handle chat message
    if (!body.message) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          message: 'Message is required',
        }),
      };
    }

    // Build context
    const contextText = buildContextText(body.context);

    // Build messages for OpenAI
    const messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }> = [
      {
        role: 'system',
        content: `${SYSTEM_PROMPT}\n\nCurrent sermon context:\n${contextText}`,
      },
    ];

    // Add conversation history
    if (body.conversationHistory && body.conversationHistory.length > 0) {
      // Limit to last 10 messages to avoid token overflow
      const recentHistory = body.conversationHistory.slice(-10);
      messages.push(
        ...recentHistory.map((msg) => ({
          role: msg.role as 'user' | 'assistant',
          content: msg.content,
        }))
      );
    }

    // Add current message
    messages.push({
      role: 'user',
      content: body.message,
    });

    // Call OpenAI
    const response = await openai.chat.completions.create({
      model: 'gpt-4',
      messages,
      temperature: 0.7,
      max_tokens: 1000,
    });

    const aiResponse = response.choices[0].message.content;

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        data: {
          response: aiResponse,
        },
      }),
    };
  } catch (error) {
    console.error('Chat error:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: error instanceof Error ? error.message : 'Internal server error',
      }),
    };
  }
};

function buildContextText(context: ChatRequest['context']): string {
  let text = `Title: ${context.title}\n`;
  text += `Service Type: ${context.serviceType}\n`;
  text += `Date: ${context.date}\n`;

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
