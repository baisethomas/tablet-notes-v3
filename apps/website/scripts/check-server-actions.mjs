import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Run after next build. This public download site intentionally exposes no
// Server Actions. Fail if a future import makes the legacy email action live.
const manifest = JSON.parse(await readFile(new URL('../.next/server/server-reference-manifest.json', import.meta.url), 'utf8'));
for (const runtime of ['node', 'edge']) {
  assert.ok(manifest[runtime], `Missing ${runtime} action manifest`);
  assert.equal(Object.keys(manifest[runtime]).length, 0, `Unexpected ${runtime} Server Actions: review public reachability before shipping`);
}
console.log('PASS: production build registers no Server Actions');
