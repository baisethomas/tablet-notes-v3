const test = require('node:test');
const assert = require('node:assert/strict');
const { isValidBibleEndpoint } = require('../bibleEndpoint');

test('accepts the bibles list endpoint', () => {
  assert.equal(isValidBibleEndpoint('bibles'), true);
});

test('accepts a multi-segment verse path (the case sanitizeText used to break)', () => {
  assert.equal(isValidBibleEndpoint('bibles/06125adad2d5898a-01/verses/JHN.3.16'), true);
});

test('accepts a passage range path', () => {
  assert.equal(isValidBibleEndpoint('bibles/06125adad2d5898a-01/passages/JHN.3.16-JHN.3.18'), true);
});

test('accepts a books path', () => {
  assert.equal(isValidBibleEndpoint('bibles/06125adad2d5898a-01/books'), true);
});

test('accepts a search path with a percent-encoded query', () => {
  assert.equal(isValidBibleEndpoint('bibles/06125adad2d5898a-01/search?query=love%20joy&limit=10'), true);
});

test('rejects path traversal', () => {
  assert.equal(isValidBibleEndpoint('bibles/../../etc/passwd'), false);
});

test('rejects absolute / protocol-relative URLs', () => {
  assert.equal(isValidBibleEndpoint('/etc/passwd'), false);
  assert.equal(isValidBibleEndpoint('//evil.com/x'), false);
  assert.equal(isValidBibleEndpoint('https://evil.com/x'), false);
});

test('rejects a leading-slash or empty segment', () => {
  assert.equal(isValidBibleEndpoint('bibles//verses'), false);
  assert.equal(isValidBibleEndpoint('/bibles'), false);
});

test('rejects spaces and angle brackets (injection)', () => {
  assert.equal(isValidBibleEndpoint('bibles/<script>'), false);
  assert.equal(isValidBibleEndpoint('bibles/id verses'), false);
});

test('rejects more than one query separator', () => {
  assert.equal(isValidBibleEndpoint('bibles/id/search?a=1?b=2'), false);
});

test('rejects empty and overlong endpoints', () => {
  assert.equal(isValidBibleEndpoint(''), false);
  assert.equal(isValidBibleEndpoint('a'.repeat(201)), false);
  assert.equal(isValidBibleEndpoint(null), false);
  assert.equal(isValidBibleEndpoint(undefined), false);
});
