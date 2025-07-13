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

exports.handler = async (event, context) => {
  // Set up CORS
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  if (event.httpMethod === 'OPTIONS') {
    return {
        statusCode: 200,
        headers,
        body: ''
    };
  }

  if (event.httpMethod !== 'GET' && event.httpMethod !== 'POST') {
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
    console.log(`[bible-api] Authenticated user: ${user.id}`);

    // Get the Bible API key from environment variables
    const bibleApiKey = process.env.BIBLE_API_KEY;
    if (!bibleApiKey) {
      throw new Error('Bible API key not configured');
    }

    const baseURL = 'https://api.scripture.api.bible/v1';
    
    // Parse request parameters
    let endpoint, requestMethod = 'GET';
    
    if (event.httpMethod === 'GET') {
      // Extract endpoint from query parameters
      endpoint = event.queryStringParameters?.endpoint;
    } else if (event.httpMethod === 'POST') {
      const body = JSON.parse(event.body);
      endpoint = body.endpoint;
      requestMethod = body.method || 'GET';
    }

    if (!endpoint) {
      console.error('[bible-api] No endpoint provided');
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'endpoint parameter is required' })
      };
    }

    // Construct full URL
    const url = `${baseURL}/${endpoint}`;
    
    console.log(`[bible-api] Making ${requestMethod} request to: ${url}`);
    console.log(`[bible-api] Endpoint received: "${endpoint}"`);

    // Make request to Bible API
    const response = await fetch(url, {
      method: requestMethod,
      headers: {
        'api-key': bibleApiKey,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[bible-api] Bible API error ${response.status}:`, errorText);
      
      // Handle specific Bible API errors gracefully
      if (response.status === 404) {
        // Verse not found - return a proper response instead of throwing
        return {
          statusCode: 200,
          headers,
          body: JSON.stringify({ 
            data: null,
            error: 'Verse not found',
            status: 404,
            userId: user.id
          })
        };
      } else if (response.status >= 400 && response.status < 500) {
        // Client error - return the error information
        return {
          statusCode: 200,
          headers,
          body: JSON.stringify({ 
            data: null,
            error: `Bible API client error: ${response.status} ${response.statusText}`,
            details: errorText,
            userId: user.id
          })
        };
      }
      
      throw new Error(`Bible API request failed: ${response.status} ${response.statusText} - ${errorText}`);
    }

    const data = await response.json();
    
    console.log(`[bible-api] Request completed successfully for user ${user.id}`);
    console.log(`[bible-api] Response data:`, JSON.stringify(data, null, 2));

    return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ 
            data,
            userId: user.id // Include user ID for client verification
        })
    };

  } catch (error) {
    console.error('[bible-api] Request error:', error.message);
    
    // Return appropriate error status based on error type
    const statusCode = error.message.includes('Authorization') || 
                      error.message.includes('Invalid') || 
                      error.message.includes('expired') ? 401 : 500;
    
    return {
        statusCode,
        headers,
        body: JSON.stringify({ 
            error: statusCode === 401 ? 'Authentication required' : 'Bible API request failed',
            details: error.message 
        })
    };
  }
}