import { AssemblyAI } from 'assemblyai';
import { createClient } from '@supabase/supabase-js';

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
    const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
    const { filePath } = req.body;

    if (!filePath) {
      return res.status(400).json({ error: 'filePath is required' });
    }

    // Get the public URL for the file from Supabase Storage
    const { data: urlData } = supabase.storage
      .from('audio-files')
      .getPublicUrl(filePath);
    
    if (!urlData || !urlData.publicUrl) {
        return res.status(404).json({ error: 'Could not find the public URL for the file.' });
    }

    const audioUrl = urlData.publicUrl;

    console.log('Starting transcription for:', audioUrl);

    const client = new AssemblyAI(process.env.ASSEMBLYAI_API_KEY);
    const transcript = await client.transcripts.create({
      audio_url: audioUrl,
      speaker_labels: true,
      auto_highlights: true
    });

    console.log('Transcription completed:', transcript.id);

    res.status(200).json({
      id: transcript.id,
      text: transcript.text,
      segments: transcript.utterances || [],
      status: transcript.status
    });

  } catch (error) {
    console.error('Transcription error:', error);
    res.status(500).json({ 
      error: 'Transcription failed', 
      details: error.message 
    });
  }
}