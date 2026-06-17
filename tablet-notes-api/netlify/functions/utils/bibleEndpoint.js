/**
 * Validates the `endpoint` forwarded to api.scripture.api.bible.
 *
 * The previous approach ran Validator.sanitizeText(..., { allowHtml: false }),
 * which HTML-escapes '/' (→ &#x2F;) and corrupts every multi-segment Bible path
 * (bibles/{id}/verses/{id}). This validates against a strict allowlist instead,
 * preserving slashes and query strings while blocking traversal, absolute URLs,
 * and injection characters (TAB-48).
 *
 * Accepts a relative API.Bible path with an optional query string, e.g.
 *   bibles
 *   bibles/06125adad2d5898a-01/verses/JHN.3.16
 *   bibles/06125adad2d5898a-01/search?query=love&limit=10
 *
 * @returns {boolean}
 */
function isValidBibleEndpoint(endpoint) {
  if (typeof endpoint !== 'string') return false;
  if (endpoint.length === 0 || endpoint.length > 200) return false;

  // No path traversal, no protocol-relative/absolute URLs, no empty segments.
  if (endpoint.includes('..')) return false;
  if (endpoint.includes('//')) return false;
  if (endpoint.includes(':')) return false;
  if (endpoint.startsWith('/')) return false;

  const parts = endpoint.split('?');
  if (parts.length > 2) return false;

  const [path, query] = parts;

  // Path: slash-separated segments of [A-Za-z0-9._-].
  if (!/^[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*$/.test(path)) return false;

  // Query (optional): key=value pairs; values may be percent-encoded.
  if (query !== undefined) {
    if (!/^[A-Za-z0-9._~%+=&-]*$/.test(query)) return false;
  }

  return true;
}

module.exports = { isValidBibleEndpoint };
