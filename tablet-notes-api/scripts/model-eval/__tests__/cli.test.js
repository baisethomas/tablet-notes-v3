'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { args, selectTranscripts, manifestRow } = require('../lib/cli');

test('arguments: values, bare flags and positionals', () => {
  const a = args(['run', '--run', 'smoke', '--models', 'a/b [x, y];c/d', '--all-users', '--repeats', '2']);
  assert.deepEqual(a._, ['run']);
  assert.equal(a.run, 'smoke');
  assert.equal(a.models, 'a/b [x, y];c/d');
  assert.equal(a['all-users'], true);
  assert.equal(a.repeats, '2');
  assert.equal(args(['pull', '--all-users', '--n', '5'])['all-users'], true);
  assert.equal(args(['run', '--run=smoke', '--models=--odd label']).models, '--odd label');
  assert.equal(args(['run', '--run=a=b']).run, 'a=b');
});

test('a value flag with no value, or an unknown flag, is an error and not a silent switch', () => {
  assert.throws(() => args(['report', '--run']), /--run needs a value/);
  assert.throws(() => args(['run', '--run', 'x', '--models', '--judges', 'a']), /--models needs a value/);
  assert.throws(() => args(['run', '--run', 'x', '--models', '--odd label']), /--models needs a value/);
  assert.throws(() => args(['run', '--run=']), /--run needs a value/);
  assert.throws(() => args(['run', '--run', 'x', '--model', 'a']), /unknown option --model/);
  assert.throws(() => args(['pull', '--all-users=yes']), /--all-users takes no value/);
});

const LIMITS = { minChars: 100, maxChars: 1000 };
const body = (seed, len) => `${seed} `.repeat(len).slice(0, len);
const t = (id, serviceType, text) => ({ id, source: 'supabase', serviceType, durationSec: 1800, text });

test('clips, oversized transcripts and a second recording of the same sermon are left out', () => {
  const all = [
    t('a', 'Sermon', body('alpha', 700)),
    t('b', 'Sermon', body('alpha', 800)),          // same opening 600 characters as a: the same sermon again
    t('c', 'Sermon', body('clip', 50)),
    t('d', 'Sermon', body('long', 5000)),
    t('e', 'Bible Study', body('echo', 500)),
  ];
  const { usable, picked } = selectTranscripts(all, 10, LIMITS);
  assert.deepEqual(usable.map(x => x.id), ['a', 'e']);
  assert.deepEqual(picked.map(x => x.id).sort(), ['a', 'e']);
});

test('the sample is spread across service types before any type gets a second one', () => {
  const all = [];
  for (let i = 0; i < 6; i++) all.push(t(`s${i}`, 'Sermon', body(`sermon${i}`, 300)));
  for (let i = 0; i < 2; i++) all.push(t(`b${i}`, 'Bible Study', body(`study${i}`, 300)));
  all.push(t('y0', 'Youth', body('youth0', 300)));
  const { picked } = selectTranscripts(all, 5, LIMITS);
  assert.equal(picked.length, 5);
  assert.deepEqual(new Set(picked.slice(0, 3).map(x => x.serviceType)), new Set(['Sermon', 'Bible Study', 'Youth']));
  const count = (type) => picked.filter(x => x.serviceType === type).length;
  assert.deepEqual([count('Sermon'), count('Bible Study'), count('Youth')], [2, 2, 1]);
});

test('the same pull selects the same transcripts whatever order it arrives in', () => {
  const all = Array.from({ length: 9 }, (_, i) => t(`id${i}`, i % 2 ? 'Sermon' : 'Bible Study', body(`text${i}`, 300)));
  const first = selectTranscripts(all, 4, LIMITS).picked.map(x => x.id);
  const again = selectTranscripts([...all].reverse(), 4, LIMITS).picked.map(x => x.id);
  assert.deepEqual(again, first);
  assert.equal(all[0].id, 'id0');   // the input is not reordered
});

test('asking for more than there is returns what there is', () => {
  assert.equal(selectTranscripts([t('a', 'Sermon', body('alpha', 300))], 12, LIMITS).picked.length, 1);
  assert.deepEqual(selectTranscripts([], 12, LIMITS), { usable: [], picked: [] });
});

test('a manifest row alternates tiers and carries no transcript text', () => {
  const row0 = manifestRow(t('a', 'Sermon', body('alpha', 300)), 0);
  const row1 = manifestRow(t('b', 'Sermon', body('beta', 300)), 1);
  assert.deepEqual(row0, { id: 'a', source: 'supabase', serviceType: 'Sermon', chars: 300, durationSec: 1800, tier: 'premium' });
  assert.equal(row1.tier, 'basic');
  assert.equal('text' in row0, false);
});
