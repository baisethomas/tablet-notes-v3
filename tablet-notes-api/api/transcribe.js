import { createClient } from '@supabase/supabase-js';
import { AssemblyAI } from 'assemblyai';

export default async function handler(req, res) {
    console.log("Transcribe endpoint hit");
    if (req.method !== 'POST') {
        return res.status(405).json({ message: 'Method Not Allowed' });
    }

    const { filePath } = req.body;
    console.log("Received filePath:", filePath);

    if (!filePath) {
        return res.status(400).json({ error: 'filePath is required' });
    }

    try {
        const supabaseUrl = process.env.SUPABASE_URL;
        const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
        console.log("Supabase URL:", supabaseUrl ? "Loaded" : "Missing");

        if (!supabaseUrl || !supabaseKey) {
            console.error("Supabase environment variables are not set.");
            return res.status(500).json({ error: 'Server configuration error: Supabase variables missing.' });
        }

        const supabase = createClient(supabaseUrl, supabaseKey);
        console.log("Supabase client created.");

        const bucketName = 'audio-files';
        console.log(`Attempting to download from bucket: ${bucketName}, file: ${filePath}`);

        const { data: blobData, error: downloadError } = await supabase.storage.from(bucketName).download(filePath);

        if (downloadError) {
            console.error("Supabase download error:", downloadError);
            return res.status(500).json({ error: 'Failed to download audio file from storage.', details: downloadError.message });
        }

        console.log("File downloaded from Supabase successfully.");

        const assembly = new AssemblyAI({
            apiKey: process.env.ASSEMBLYAI_API_KEY,
        });

        console.log("AssemblyAI client created. Starting transcription...");
        const transcript = await assembly.transcripts.create({
            audio: blobData,
            speaker_labels: true,
        });
        
        console.log("Transcription successful:", transcript.id);

        res.status(200).json({
            id: transcript.id,
            text: transcript.text,
            segments: transcript.words, 
            status: transcript.status
        });

    } catch (error) {
        console.error("An unexpected error occurred:", error);
        res.status(500).json({ error: 'A server error has occurred' });
    }
}