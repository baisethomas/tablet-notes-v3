const { createClient } = require('@supabase/supabase-js');
const { randomUUID } = require('crypto');

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
    // In Netlify, the body is a string, so we need to parse it.
    const { fileName } = JSON.parse(event.body);

    if (!fileName) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'fileName is required' }),
      };
    }

    // Generate a unique path for the file to avoid overwrites
    const fileExt = fileName.split('.').pop();
    const uniqueFileName = `${randomUUID()}.${fileExt}`;
    const filePath = `public/${uniqueFileName}`;

    const { data, error } = await supabase.storage
      .from('audio-files')
      .createSignedUploadUrl(filePath);

    if (error) {
      console.error('Error creating signed URL:', error);
      throw error;
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        uploadUrl: data.signedUrl,
        path: data.path,
        token: data.token,
      }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: 'Failed to generate upload URL',
        details: error.message,
      }),
    };
  }
}; 