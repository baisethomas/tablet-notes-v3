import OpenAI from 'openai';

export default async function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    const { text, serviceType = 'sermon' } = req.body;

    if (!text) {
      return res.status(400).json({ error: 'text is required' });
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

    res.status(200).json({ 
      summary,
      usage: completion.usage
    });

  } catch (error) {
    console.error('Summarization error:', error);
    res.status(500).json({ 
      error: 'Summarization failed', 
      details: error.message 
    });
  }
}