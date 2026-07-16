const { handleSupportWebhook } = require('../src/supportWebhookHandler');

module.exports = async function supportWebhook(request, response) {
  const rawBody = await readRawBody(request);
  const result = await handleSupportWebhook({
    method: request.method,
    headers: request.headers,
    rawBody
  });

  response.statusCode = result.statusCode;
  for (const [name, value] of Object.entries(result.headers)) {
    response.setHeader(name, value);
  }
  response.end(result.body);
};

async function readRawBody(request) {
  if (Buffer.isBuffer(request.body)) {
    return request.body.toString('utf8');
  }
  if (typeof request.body === 'string') {
    return request.body;
  }

  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  if (chunks.length > 0) {
    return Buffer.concat(chunks).toString('utf8');
  }

  return request.body && typeof request.body === 'object'
    ? JSON.stringify(request.body)
    : '';
}

module.exports.readRawBody = readRawBody;
