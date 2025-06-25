const { AssemblyAI } = require('assemblyai');

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
    const { id } = JSON.parse(event.body);
    if (!id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'id is required' }),
      };
    }

    const assembly = new AssemblyAI({
      apiKey: process.env.ASSEMBLYAI_API_KEY,
    });

    // Fetch the transcript status from AssemblyAI
    const transcript = await assembly.transcripts.get(id);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        id: transcript.id,
        text: transcript.text,
        segments: transcript.words, // or transcript.segments if available
        status: transcript.status,
      }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: 'Failed to fetch transcription status',
        details: error.message,
      }),
    };
  }
}; 