const { createClient } = require('@supabase/supabase-js');

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

// Helper function to check if user has pro/premium subscription
function hasLiveTranscriptionAccess(user) {
  // Check if user has pro or premium tier
  const tier = user.user_metadata?.subscription_tier || 'free';
  return tier === 'pro' || tier === 'premium';
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
    console.log(`[assemblyai-live-token] Authenticated user: ${user.id}`);

    // Check if user has access to live transcription
    if (!hasLiveTranscriptionAccess(user)) {
      return {
        statusCode: 403,
        headers,
        body: JSON.stringify({ 
          error: 'Live transcription requires Pro or Premium subscription',
          requiredTier: 'pro'
        })
      };
    }

    // Get the AssemblyAI API key from environment variables
    const assemblyaiApiKey = process.env.ASSEMBLYAI_API_KEY;
    if (!assemblyaiApiKey) {
      throw new Error('AssemblyAI API key not configured');
    }

    // Generate temporary session token from AssemblyAI
    console.log(`[assemblyai-live-token] Generating session token for user ${user.id}`);
    
    const response = await fetch('https://api.assemblyai.com/v2/realtime/token', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${assemblyaiApiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        expires_in: 3600 // 1 hour
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[assemblyai-live-token] AssemblyAI API error: ${response.status} ${errorText}`);
      throw new Error(`AssemblyAI API error: ${response.status}`);
    }

    const tokenData = await response.json();
    console.log(`[assemblyai-live-token] Session token generated successfully for user ${user.id}`);

    return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ 
            sessionToken: tokenData.token,
            expiresIn: tokenData.expires_in,
            userId: user.id // Include user ID for client verification
        })
    };

  } catch (error) {
    console.error('[assemblyai-live-token] Error:', error.message);
    
    // Return appropriate error status based on error type
    const statusCode = error.message.includes('Authorization') || 
                      error.message.includes('Invalid') || 
                      error.message.includes('expired') ? 401 : 500;
    
    return {
        statusCode,
        headers,
        body: JSON.stringify({ 
            error: statusCode === 401 ? 'Authentication required' : 'Failed to generate session token',
            details: error.message 
        })
    };
  }
}