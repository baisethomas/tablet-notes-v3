'use strict';

// Reading and writing the run's JSON files.
//
// A write goes to a temporary file beside the target and is renamed into
// place, so a process killed mid-write leaves either the old file or none,
// never half of one. A result file that still cannot be parsed (written by an
// older version, or damaged some other way) is read as absent: `run` and
// `judge` redo it, and `report` counts it as missing evidence.

const fs = require('node:fs');
const path = require('node:path');

const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));

function readJsonOrNull(f) {
  let raw;
  try { raw = fs.readFileSync(f, 'utf8'); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
  try { return JSON.parse(raw); } catch (_) { return null; }
}

function writeText(f, text) {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(tmp, text);
    fs.renameSync(tmp, f);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

const writeJson = (f, d) => writeText(f, JSON.stringify(d, null, 2));

module.exports = { readJson, readJsonOrNull, writeJson, writeText };
