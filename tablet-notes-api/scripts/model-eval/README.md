# Replacement-model evaluation

A repeatable test for choosing the model behind `summarize`, `chat` and suggested
questions. It sends real sermon transcripts through candidate models with the
production prompt and parameters, then scores every output against the
standards below. The incumbent runs through the same harness, so every
candidate is compared with what users get today.

## The standards

A candidate must pass every gate. Passing candidates are then ranked by quality.
Thresholds live in `config.json`.

### Gates the code can decide (every generation)

| Gate | Threshold | Why it exists |
|---|---|---|
| Completes: non-empty, `finish_reason = stop`, inside 55 s | 100% | A truncated or empty summary is stored as a finished one. Production aborts at 55 s in total, so a later reply counts as a failed generation, retries included. |
| First line parses as `TITLE: ...` | 100% | `summarize.js` reads the sermon title from it. |
| All required sections present for the tier | 95% | The app shows these sections; premium adds Application. |
| Scripture References section holds a parseable reference | 90% | Scripture reminders are built from it (TAB-119, TAB-120). |
| Latency p95 | 45 s | Headroom under the 55 s abort. |
| Cost per summary | at most 2x the incumbent | |
| Suggested questions return the JSON contract | 100% | `chat.js` parses it with `JSON.parse`. |
| Off-topic chat question is redirected, not answered | 100% | Required by the chat system prompt. The code checks the reply points back to the sermon and gives no voting or investing advice; every judge must then agree it answered neither question. |

### Gates a judge decides (first generation of each transcript)

Two judge models from different vendors grade each summary against its
transcript without knowing which model wrote it. Scores are 1 to 5.

| Gate | Threshold |
|---|---|
| Mean faithfulness | no more than 0.15 below the incumbent |
| Mean scripture accuracy | no more than 0.15 below the incumbent |
| Worst single faithfulness score | at least 3 |
| Weighted quality | no more than 2 points below the incumbent |

Quality is a 0-100 score: faithfulness 35%, scripture accuracy 25%, coverage
20%, focus 10%, clarity 10%. Faithfulness and scripture carry the weight
because a summary that misreports the sermon is worse than a thin one.

A verdict needs its evidence. Every gradable first generation and every off-topic
reply must have a judgment from every judge, for the candidate and for the incumbent, or the
candidate is reported as INCOMPLETE instead of PASS. A measured failure still
reads FAIL. A judgment is tied to a hash of the summary it graded, so
regenerating a model's output regrades it instead of reusing old scores.

The judged gates are relative to the incumbent on purpose. The judges grade
hard: on the first run the incumbent averaged 3.5 for faithfulness, so an
absolute bar of 4.0 would have failed the model users have today. 4.0 is kept
as a reported target.

### Reported, not gated

Mean faithfulness against the 4.0 target. References to a book the speaker
never named: usually the model recognising a verse the speaker quoted without
citing it, which the code cannot tell from an invented one, so the judges'
scripture score decides. Premium sections appearing in basic output, share of quoted text found verbatim
in the transcript, share of cited chapters found in the transcript, unsupported
claims per summary, how often a run exceeded the 55 s budget, and each judge's
score separately so a judge favouring its own vendor is visible.

## Drop-in versus tuned

A bare model id in `config.json` is tested with production's request unchanged
(2,000 output tokens, no reasoning setting). That answers "can I change only
the model string?". For most current models the answer is no: they reason by
default and write longer summaries, so they hit the token cap. The
`{ label, model, params }` form tests the same model with the request changes a
real swap would ship, and the label says what they are.

## What it does not measure

- Latency is measured through OpenRouter, not the provider's own API. It
  includes retried attempts and the backoff between them.
- The reference parser is this tool's, not the app's Swift analyzer (TAB-121).
- Chat answer quality is not judged; only the two chat contracts above. The
  off-topic gate uses one fixed question about voting and stocks.
- With 12 transcripts a rate moves about 4 points per generation. Treat a
  one-run difference near a threshold as a tie and raise `--n`.

## Running it

```
node eval.js pull   --source supabase --users <uuid,uuid> --n 12
node eval.js run    --run 2026-11-22
node eval.js judge  --run 2026-11-22
node eval.js report --run 2026-11-22
node --test __tests__/*.test.js
```

`run` and `judge` skip work that already has a result file, so an interrupted
run resumes. Delete a model's folder under `runs/<name>/gen/` to redo it.
`--models "a;b"` limits `run` to some labels, and `--judges a,b` overrides the
judges (one judge roughly halves the cost). `judge` records the judges it used
in `runs/<name>/judges.json` and `report` reads that, so the two cannot
disagree. The report is written to
`runs/<name>/report.md` with the raw numbers in `scores.json`.

### Transcript sources

- `--source supabase` reads the `transcripts` table with GET requests only.
  `--users` is required: it names whose sermons are sent to third-party models.
- `--source assemblyai` lists completed transcripts from the AssemblyAI account.
  It needs `ASSEMBLYAI_API_KEY` in the environment; the Netlify copy is a masked
  secret and cannot be read back. This source spans every user's recordings
  and cannot be filtered by user, so it refuses to run without `--all-users`.

### Keys and data handling

- `OPENROUTER_API_KEY` comes from the environment, or from the file named by
  `OPENROUTER_ENV_FILE`. The Supabase key is resolved through the `supabase` CLI.
  Nothing is written to disk.
- Every OpenRouter request sets `provider.data_collection = "deny"`, so a model
  only reachable through a provider that retains prompts fails rather than runs.
  A candidate's `params` cannot override it.
- `data/` and `runs/` hold transcripts and summaries. Both are gitignored.

### Prompts

`lib/prompt.js` reads the prompts and parameters out of `summarize.js` and
`chat.js` at run time and throws if their shape changes, so the eval cannot
drift from production. Candidates are listed in `config.json`; per-model request
overrides (for example a reasoning setting) go in the `{ label, model, params }` candidate form.
