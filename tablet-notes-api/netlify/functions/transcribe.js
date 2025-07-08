const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');

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

// Helper function to verify user owns the file
function verifyFileOwnership(filePath, userId) {
  // File path should be in format: {userId}/{filename}
  const pathParts = filePath.split('/');
  if (pathParts.length < 2 || pathParts[0] !== userId) {
    throw new Error('Access denied: You can only transcribe your own files');
  }
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

    console.log("[transcribe] Transcribe endpoint hit");
    if (event.httpMethod !== 'POST') {
        return {
            statusCode: 405,
            headers,
            body: JSON.stringify({ message: 'Method Not Allowed' })
        };
    }

    try {
        const supabaseUrl = process.env.SUPABASE_URL;
        const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
        
        if (!supabaseUrl || !supabaseKey) {
            console.error("[transcribe] Supabase environment variables are not set.");
            return {
                statusCode: 500,
                headers,
                body: JSON.stringify({ error: 'Server configuration error: Supabase variables missing.' })
            };
        }

        const supabase = createClient(supabaseUrl, supabaseKey);
        
        // Authenticate user
        const user = await getAuthenticatedUser(event.headers.authorization, supabase);
        console.log(`[transcribe] Authenticated user: ${user.id}`);

        const { filePath } = JSON.parse(event.body);
        console.log("[transcribe] Received filePath:", filePath);

        if (!filePath) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({ error: 'filePath is required' })
            };
        }

        // Verify user owns the file
        verifyFileOwnership(filePath, user.id);
        console.log(`[transcribe] File ownership verified for user ${user.id}`);

        const bucketName = 'audio-files';
        console.log(`[transcribe] Attempting to download from bucket: ${bucketName}, file: ${filePath}`);

        const { data: blobData, error: downloadError } = await supabase.storage.from(bucketName).download(filePath);

        if (downloadError) {
            console.error("[transcribe] Supabase download error:", downloadError);
            return {
                statusCode: 500,
                headers,
                body: JSON.stringify({ error: 'Failed to download audio file from storage.', details: downloadError.message })
            };
        }

        console.log("[transcribe] File downloaded from Supabase successfully.");

        const assembly = new AssemblyAI({
            apiKey: process.env.ASSEMBLYAI_API_KEY,
        });

        console.log("[transcribe] AssemblyAI client created. Starting transcription...");
        const transcript = await assembly.transcripts.submit({
            audio: blobData,
            speaker_labels: true,
        });
        
        console.log(`[transcribe] Transcription submitted successfully for user ${user.id}:`, transcript.id);

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                id: transcript.id,
                text: transcript.text,
                segments: transcript.words, 
                status: transcript.status,
                userId: user.id // Include user ID for client verification
            })
        };

    } catch (error) {
        console.error("[transcribe] Error occurred:", error.message);
        
        // Return appropriate error status based on error type
        const statusCode = error.message.includes('Authorization') || 
                          error.message.includes('Invalid') || 
                          error.message.includes('expired') ||
                          error.message.includes('Access denied') ? 401 : 500;
        
        return {
            statusCode,
            headers,
            body: JSON.stringify({ 
                error: statusCode === 401 ? 'Authentication required' : 'A server error has occurred',
                details: error.message 
            })
        };
    }
}