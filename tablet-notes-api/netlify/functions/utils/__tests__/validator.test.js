const test = require('node:test');
const assert = require('node:assert/strict');
const { Validator } = require('../validator');

// --- sanitizeLLMText (TAB-68): LLM-bound text is never HTML-escaped ---

test('sanitizeLLMText preserves apostrophes, quotes, and slashes', () => {
  const input = `God's grace isn't earned — "come as you are" and/or stay.`;
  assert.equal(Validator.sanitizeLLMText(input), input);
});

test('sanitizeLLMText preserves newlines and trims outer whitespace', () => {
  assert.equal(Validator.sanitizeLLMText('  line one\nline two  '), 'line one\nline two');
});

test('sanitizeLLMText strips control characters but keeps tabs', () => {
  assert.equal(Validator.sanitizeLLMText('a\x00b\x1Fc\td'), 'abc\td');
});

test('sanitizeLLMText truncates to maxLength', () => {
  assert.equal(Validator.sanitizeLLMText('abcdef', { maxLength: 3 }), 'abc');
});

test('sanitizeLLMText returns empty string for non-string input', () => {
  assert.equal(Validator.sanitizeLLMText(null), '');
  assert.equal(Validator.sanitizeLLMText(12345), '');
});

test('sanitizeText still HTML-escapes (HTML sinks unchanged)', () => {
  assert.equal(Validator.sanitizeText(`a'b`, { allowHtml: false }), 'a&#x27;b');
});

// --- summarization schema (TAB-68): serviceType survives validation ---

const validSummarization = {
  text: 'x'.repeat(100),
  serviceType: 'Bible Study',
  length: 'medium'
};

test('summarization schema passes serviceType through', () => {
  const result = Validator.validate(validSummarization, 'summarization');
  assert.equal(result.valid, true);
  assert.equal(result.data.serviceType, 'Bible Study');
});

test('summarization schema accepts the app service labels', () => {
  for (const label of ['Sermon', 'Sunday Service', 'Youth Group', 'Conference', 'Prayer Meeting', "Pastor's Class"]) {
    const result = Validator.validate({ ...validSummarization, serviceType: label }, 'summarization');
    assert.equal(result.valid, true, `expected "${label}" to validate`);
    assert.equal(result.data.serviceType, label);
  }
});

test('summarization schema remains valid without serviceType', () => {
  const { serviceType, ...rest } = validSummarization;
  const result = Validator.validate(rest, 'summarization');
  assert.equal(result.valid, true);
  assert.equal(result.data.serviceType, undefined);
});

test('summarization schema rejects serviceType with disallowed characters', () => {
  for (const bad of ['<script>', 'a'.repeat(51), 'type\nnewline', 'semi;colon']) {
    const result = Validator.validate({ ...validSummarization, serviceType: bad }, 'summarization');
    assert.equal(result.valid, false, `expected "${bad}" to be rejected`);
  }
});

// --- processing jobs (TAB-72) ---

const validProcessingJob = { sermonLocalId: '11111111-1111-4111-8111-111111111111' };

test('processingJob schema accepts a request with no filePath', () => {
  // The normal shape: the server resolves audio_file_path from the sermon row
  // it wrote itself, so a retry or a second device needs no client-held path.
  const result = Validator.validate(validProcessingJob, 'processingJob');
  assert.equal(result.valid, true);
  assert.equal(result.data.filePath, undefined);
  assert.equal(result.data.kind, 'transcription');
});

test('processingJob schema still accepts an explicit filePath', () => {
  const result = Validator.validate(
    { ...validProcessingJob, filePath: 'user-a/audio.m4a' },
    'processingJob'
  );
  assert.equal(result.valid, true);
  assert.equal(result.data.filePath, 'user-a/audio.m4a');
});

test('processingJob schema still requires a real sermonLocalId', () => {
  assert.equal(Validator.validate({}, 'processingJob').valid, false);
  assert.equal(Validator.validate({ sermonLocalId: 'not-a-uuid' }, 'processingJob').valid, false);
});
