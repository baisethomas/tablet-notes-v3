const { createClient } = require('@supabase/supabase-js');
const { randomUUID } = require('crypto');

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
    console.log(`[generate-upload-url] Authenticated user: ${user.id}`);
    
    // Parse request body
    const { fileName } = JSON.parse(event.body);

    if (!fileName) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'fileName is required' }),
      };
    }

    // Generate a unique path for the file using user ID for organization
    const fileExt = fileName.split('.').pop();
    const uniqueFileName = `${randomUUID()}.${fileExt}`;
    const filePath = `${user.id}/${uniqueFileName}`; // Organize by user ID

    console.log(`[generate-upload-url] Creating signed URL for path: ${filePath}`);

    const { data, error } = await supabase.storage
      .from('audio-files')
      .createSignedUploadUrl(filePath);

    if (error) {
      console.error('Error creating signed URL:', error);
      throw error;
    }

    console.log(`[generate-upload-url] Successfully created signed URL for user ${user.id}`);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        uploadUrl: data.signedUrl,
        path: data.path,
        token: data.token,
        userId: user.id, // Include user ID in response for client-side verification
      }),
    };
  } catch (error) {
    console.error('[generate-upload-url] Error:', error.message);
    
    // Return appropriate error status based on error type
    const statusCode = error.message.includes('Authorization') || 
                      error.message.includes('Invalid') || 
                      error.message.includes('expired') ? 401 : 500;
    
    return {
      statusCode,
      headers,
      body: JSON.stringify({
        error: statusCode === 401 ? 'Authentication required' : 'Failed to generate upload URL',
        details: error.message,
      }),
    };
  }
};