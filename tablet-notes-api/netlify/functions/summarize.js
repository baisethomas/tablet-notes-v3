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
          content: `You are a helpful assistant that creates comprehensive summaries of ${serviceType} content. 
          
          Please structure your response with the following sections:
          
          **Summary**: A concise overview of the main points
          **Key Points**: 3-5 bullet points of the most important takeaways
          **Scripture References**: Any Bible verses or religious texts mentioned
          **Application**: How the audience can apply these teachings
          
          Keep the summary engaging and easy to understand.`
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