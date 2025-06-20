import { AssemblyAI } from 'assemblyai';

const client = new AssemblyAI(process.env.ASSEMBLYAI_API_KEY);

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { audioUrl } = req.body;
    
    const transcript = await client.transcripts.create({
      audio_url: audioUrl,
      speaker_labels: true
    });

    res.status(200).json(transcript);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}