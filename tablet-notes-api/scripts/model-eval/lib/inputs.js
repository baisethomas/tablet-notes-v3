'use strict';

// A run's inputs. `pull` replaces data/ wholesale, so a run that kept only
// transcript ids would later be judged against whatever text those ids (or
// none of them) point at now. The first `run` therefore copies the selected
// transcripts into runs/<run>/inputs/, and every later step of that run reads
// only that copy. runs/ is gitignored, like data/.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const writeJson = (f, d) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(d, null, 2)); };

const inputsDir = (runDir) => path.join(runDir, 'inputs');
const hasInputs = (runDir) => fs.existsSync(path.join(inputsDir(runDir), 'manifest.json'));

function readSet(dir) {
  const manifest = readJson(path.join(dir, 'manifest.json'));
  return manifest.map(m => ({ ...m, text: readJson(path.join(dir, 'transcripts', `${m.id}.json`)).text }));
}

// Copy the current pull into the run, once. A run that already has inputs
// keeps them: a later pull never changes what an existing run is about.
function snapshotInputs(dataDir, runDir) {
  if (hasInputs(runDir)) return loadInputs(runDir);
  const set = readSet(dataDir);
  const dir = inputsDir(runDir);
  for (const t of set) {
    const { text, ...meta } = t;
    writeJson(path.join(dir, 'transcripts', `${t.id}.json`), { ...meta, text });
  }
  // Written last, so a half-finished copy is not mistaken for a snapshot.
  writeJson(path.join(dir, 'manifest.json'), set.map(({ text, ...meta }) => ({ ...meta, sha: sha(text) })));
  return loadInputs(runDir);
}

// The run's own transcripts, verified against the hashes taken when they
// were copied. Throws rather than fall back to data/.
function loadInputs(runDir) {
  if (!hasInputs(runDir)) {
    throw new Error(`${path.basename(runDir)} has no input snapshot (runs/<run>/inputs/). It was created before inputs were recorded, so it cannot be judged or reported against known transcripts; start a new run.`);
  }
  const set = readSet(inputsDir(runDir));
  for (const t of set) {
    if (sha(t.text) !== t.sha) throw new Error(`input snapshot for transcript ${String(t.id).slice(0, 8)} does not match its recorded hash`);
  }
  return set;
}

module.exports = { snapshotInputs, loadInputs, hasInputs };
