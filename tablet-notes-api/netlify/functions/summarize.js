const { createClient } = require('@supabase/supabase-js');
const OpenAI = require('openai');

// Helper function to verify JWT token and get user
async function getAuthenticatedUser(authHeader, supabase) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Authorization header required');
  }

  const token = authHeader.substring(7); // Remove 'Bearer ' prefix
  
  const { data: { user }, error } = await supabase.auth.getUser(token);
  
  if (error || !user) {
    throw new Error('Invalid or expired token');
  }
  
  return user;
}

exports.handler = async (event, context) => {
  // Set up CORS
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  if (event.httpMethod === 'OPTIONS') {
    return {
        statusCode: 200,
        headers,
        body: ''
    };
  }

  if (event.httpMethod !== 'POST') {
    return {
        statusCode: 405,
        headers,
        body: JSON.stringify({ error: 'Method not allowed' })
    };
  }

  try {
    const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
    
    // Authenticate user
    const user = await getAuthenticatedUser(event.headers.authorization, supabase);
    console.log(`[summarize] Authenticated user: ${user.id}`);

    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    const { text, serviceType = 'sermon' } = JSON.parse(event.body);

    if (!text) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'text is required' })
      };
    }

    console.log(`[summarize] Starting summarization for user ${user.id}, serviceType: ${serviceType}`);

    const completion = await openai.chat.completions.create({
      model: "gpt-3.5-turbo",
      messages: [
        {
          role: "system",
          content: `You are a thoughtful theological assistant that creates comprehensive summaries of ${serviceType} content with deep respect for biblical accuracy and spiritual formation.

**Core Principles:**
- Maintain absolute faithfulness to the original sermon content - never add interpretations or applications not present
- Preserve the speaker's theological perspective and denominational context
- Use precise biblical language and avoid casual or trendy expressions
- Emphasize scriptural authority and careful exegesis

**Required Structure:**

**Brief Summary** (2-3 sentences)
Capture the sermon's central thesis and primary biblical text(s). Focus on the main theological point the speaker aimed to communicate.

**Key Points** (3-5 substantial points)
- Extract the speaker's main arguments and supporting evidence
- Include specific biblical references as the speaker used them
- Preserve theological terminology and doctrinal language
- Note any historical or cultural context the speaker provided

**Scripture References**
- List all Bible passages mentioned, cited, or alluded to
- Include book, chapter, and verse references in standard format
- Note if the speaker emphasized particular translations or textual variants
- Distinguish between primary texts and supporting passages

**Application** 
- Summarize only applications explicitly given by the speaker
- Focus on spiritual disciplines, character formation, and biblical living
- Include any specific calls to action or response the speaker requested
- Maintain the speaker's pastoral tone and intended audience context

**Deeper Dive** (Optional - for substantial theological content)
- Complex theological concepts or doctrinal teaching
- Historical background or cultural context provided
- Cross-references to other biblical passages or theological traditions
- Any scholarly insights or original language observations

**Guidelines:**
- Never speculate beyond what the speaker actually said
- Preserve denominational distinctives and theological terminology
- Maintain reverence for Scripture as the final authority
- Focus on spiritual edification rather than mere information transfer
- Keep summaries substantive yet accessible to the intended audience`
        },
        {
          role: "user",
          content: `Please summarize this ${serviceType} text: ${text}`
        }
      ],
      max_tokens: 1000,
      temperature: 0.7
    });

    const summary = completion.choices[0].message.content;
    console.log(`[summarize] Summarization completed for user ${user.id}`);

    return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ 
            summary,
            usage: completion.usage,
            userId: user.id // Include user ID for client verification
        })
    };

  } catch (error) {
    console.error('[summarize] Summarization error:', error.message);
    
    // Return appropriate error status based on error type
    const statusCode = error.message.includes('Authorization') || 
                      error.message.includes('Invalid') || 
                      error.message.includes('expired') ? 401 : 500;
    
    return {
        statusCode,
        headers,
        body: JSON.stringify({ 
            error: statusCode === 401 ? 'Authentication required' : 'Summarization failed',
            details: error.message 
        })
    };
  }
}