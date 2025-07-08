const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');

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
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 200,
      headers,
      body: '',
    };
  }

  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: 'Method not allowed' }),
    };
  }

  try {
    const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
    
    // Authenticate user
    const user = await getAuthenticatedUser(event.headers.authorization, supabase);
    console.log(`[transcribe-status] Authenticated user: ${user.id}`);

    const { id, userId } = JSON.parse(event.body);
    if (!id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'id is required' }),
      };
    }

    // Verify user can access this transcription
    // The client should pass the userId that initiated the transcription
    if (userId && userId !== user.id) {
      console.log(`[transcribe-status] Access denied: User ${user.id} tried to access transcription for user ${userId}`);
      return {
        statusCode: 403,
        headers,
        body: JSON.stringify({ error: 'Access denied: You can only check your own transcriptions' }),
      };
    }

    console.log(`[transcribe-status] Checking transcription status for job ${id}, user ${user.id}`);

    const assembly = new AssemblyAI({
      apiKey: process.env.ASSEMBLYAI_API_KEY,
    });

    // Fetch the transcript status from AssemblyAI
    const transcript = await assembly.transcripts.get(id);

    console.log(`[transcribe-status] Transcription status for user ${user.id}: ${transcript.status}`);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        id: transcript.id,
        text: transcript.text,
        segments: transcript.words,
        status: transcript.status,
        userId: user.id, // Include user ID for client verification
      }),
    };
  } catch (error) {
    console.error('[transcribe-status] Error:', error.message);
    
    // Return appropriate error status based on error type
    const statusCode = error.message.includes('Authorization') || 
                      error.message.includes('Invalid') || 
                      error.message.includes('expired') ? 401 : 500;
    
    return {
      statusCode,
      headers,
      body: JSON.stringify({
        error: statusCode === 401 ? 'Authentication required' : 'Failed to fetch transcription status',
        details: error.message,
      }),
    };
  }
};