const OpenAI = require('openai');

// Netlify functions have a default timeout of 10 seconds on the free tier.
// For longer summaries, you may need to upgrade your Netlify plan.
// See: https://docs.netlify.com/functions/overview/#function-duration

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

    console.log('Starting summarization for:', serviceType);

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
    console.log('Summarization completed');

    return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ 
            summary,
            usage: completion.usage
        })
    };

  } catch (error) {
    console.error('Summarization error:', error);
    return {
        statusCode: 500,
        headers,
        body: JSON.stringify({ 
            error: 'Summarization failed', 
            details: error.message 
        })
    };
  }
}