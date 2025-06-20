import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  // Set up CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
    const { fileName } = req.body;

    if (!fileName) {
      return res.status(400).json({ error: 'fileName is required' });
    }

    // Generate a unique path for the file to avoid overwrites
    const filePath = `public/${Date.now()}-${fileName}`;

    const { data, error } = await supabase.storage
      .from('audio-files')
      .createSignedUploadUrl(filePath);

    if (error) {
      console.error('Error creating signed URL:', error);
      throw error;
    }

    res.status(200).json({
      uploadUrl: data.signedUrl,
      path: data.path,
      token: data.token,
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to generate upload URL',
      details: error.message,
    });
  }
} 