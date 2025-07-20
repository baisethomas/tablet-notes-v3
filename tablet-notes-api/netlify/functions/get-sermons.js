const { createClient } = require('@supabase/supabase-js');
const { handleCORS, createAuthMiddleware, createErrorResponse, createSuccessResponse } = require('./utils/security');
const { withLogging } = require('./utils/logger');

exports.handler = withLogging('get-sermons', async (event, context) => {
  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'GET') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  // Apply authentication
  const authMiddleware = createAuthMiddleware();
  const authResponse = await authMiddleware(event);
  if (authResponse) {
    return authResponse;
  }

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !supabaseKey) {
      return createErrorResponse(new Error('Server configuration error'), 500);
    }
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse userId from query string
    const userId = event.queryStringParameters && event.queryStringParameters.userId;
    if (!userId) {
      return createErrorResponse(new Error('Missing userId'), 400);
    }

    // Fetch all sermons for the user
    const { data, error } = await supabase
      .from('sermons')
      .select('*')
      .eq('userId', userId);

    if (error) {
      return createErrorResponse(new Error(error.message), 500);
    }

    // Optionally, map/transform data to match RemoteSermonData if needed
    // For now, return as-is
    return createSuccessResponse(data, 200);
  } catch (error) {
    return createErrorResponse(error, 500);
  }
}); 