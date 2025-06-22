const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');

// Netlify functions have a default timeout of 10 seconds on the free tier.
// For longer transcriptions, you may need to upgrade your Netlify plan.
// See: https://docs.netlify.com/functions/overview/#function-duration

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

    console.log("Transcribe endpoint hit");
    if (event.httpMethod !== 'POST') {
        return {
            statusCode: 405,
            headers,
            body: JSON.stringify({ message: 'Method Not Allowed' })
        };
    }

    const { filePath } = JSON.parse(event.body);
    console.log("Received filePath:", filePath);

    if (!filePath) {
        return {
            statusCode: 400,
            headers,
            body: JSON.stringify({ error: 'filePath is required' })
        };
    }

    try {
        const supabaseUrl = process.env.SUPABASE_URL;
        const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
        console.log("Supabase URL:", supabaseUrl ? "Loaded" : "Missing");

        if (!supabaseUrl || !supabaseKey) {
            console.error("Supabase environment variables are not set.");
            return {
                statusCode: 500,
                headers,
                body: JSON.stringify({ error: 'Server configuration error: Supabase variables missing.' })
            };
        }

        const supabase = createClient(supabaseUrl, supabaseKey);
        console.log("Supabase client created.");

        const bucketName = 'audio-files';
        console.log(`Attempting to download from bucket: ${bucketName}, file: ${filePath}`);

        const { data: blobData, error: downloadError } = await supabase.storage.from(bucketName).download(filePath);

        if (downloadError) {
            console.error("Supabase download error:", downloadError);
            return {
                statusCode: 500,
                headers,
                body: JSON.stringify({ error: 'Failed to download audio file from storage.', details: downloadError.message })
            };
        }

        console.log("File downloaded from Supabase successfully.");

        const assembly = new AssemblyAI({
            apiKey: process.env.ASSEMBLYAI_API_KEY,
        });

        console.log("AssemblyAI client created. Starting transcription...");
        const transcript = await assembly.transcripts.submit({
            audio: blobData,
            speaker_labels: true,
        });
        
        console.log("Transcription successful:", transcript.id);

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                id: transcript.id,
                text: transcript.text,
                segments: transcript.words, 
                status: transcript.status
            })
        };

    } catch (error) {
        console.error("An unexpected error occurred:", error);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ error: 'A server error has occurred' })
        };
    }
}