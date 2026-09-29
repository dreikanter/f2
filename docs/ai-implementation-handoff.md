# AI implementation handoff — September 29

Code candidate: `95f0d29593166757d1b94de875cea272308298e1`. This completes the offline implementation for #1855 and #1850–#1854. The stack remains unmerged and unqualified for live deployment.

## Review order

Each PR has fewer than 100 added/deleted lines against its immediate parent, including tests and documentation. Review from top to bottom; ship the complete qualified stack together.

| PR | Change | Revision | Lines |
| --- | --- | --- | ---: |
| [#1870](https://github.com/dreikanter/f2/pull/1870) | Remove source-specific evaluation requirements | `a4cc7b4629ddbe254cd4fbf2ba9309d2c29b8893` | 51 |
| [#1871](https://github.com/dreikanter/f2/pull/1871) | Preserve AI source dates and timezone context | `778759d484336ab1b1a975938ee9b5c0212d057a` | 48 |
| [#1872](https://github.com/dreikanter/f2/pull/1872) | Keep generated identities stable across retries | `b91b1138514ea861eba2dc01b464b6293efb908a` | 52 |
| [#1873](https://github.com/dreikanter/f2/pull/1873) | Exercise generic AI feed content offline | `4bbdf5dacf2d8e7c1ce4e1e1a7186eb904b29e69` | 27 |
| [#1874](https://github.com/dreikanter/f2/pull/1874) | Commit AI imports atomically for safe retries | `53ad987f5747ea073df1d539dd37a8b2c1b9e193` | 91 |
| [#1875](https://github.com/dreikanter/f2/pull/1875) | Share feed history and date selection | `d3c4d737f9ce183b4c87463dfe767d2a6b882789` | 83 |
| [#1876](https://github.com/dreikanter/f2/pull/1876) | Select usable AI posts before final limits | `24294226b7415ebdc5eddbb0cb936786ca143f07` | 95 |
| [#1877](https://github.com/dreikanter/f2/pull/1877) | Allow a bounded pool of spare AI candidates | `58be51b65ea938fce4e8f4b61759909b195ed770` | 86 |
| [#1878](https://github.com/dreikanter/f2/pull/1878) | Align saved AI previews with refresh context | `f201c8aff1f3550135cc429d27aea27dbae7ebd2` | 81 |
| [#1879](https://github.com/dreikanter/f2/pull/1879) | Guard AI output processing with the run deadline | `82de70de5afc47a8a3fc9f6711020101ea38e0f0` | 59 |
| [#1880](https://github.com/dreikanter/f2/pull/1880) | Reconcile AI candidate selection counts | `d6ce337e3960129527f7f3ac553719a397e0768b` | 51 |
| [#1881](https://github.com/dreikanter/f2/pull/1881) | Keep unknown AI spend explicitly incomplete | `3cd82c07c93f10da145747c6763efe9d62e496f9` | 94 |
| [#1882](https://github.com/dreikanter/f2/pull/1882) | Make AI web retrieval an explicit capability | `bba355c4482a72f06f98ab40a59c94eeb0c245e8` | 96 |
| [#1883](https://github.com/dreikanter/f2/pull/1883) | Explain rejected AI settings in previews | `95f0d29593166757d1b94de875cea272308298e1` | 32 |

The initial inventory found an already generic RubyLLM runtime, without an X verifier or fallback orchestration to remove. #1870 removes obsolete active evaluation requirements; the saved historical baseline and working execution infrastructure remain. No temporary disablement or parallel runtime was introduced merely to reconstruct the same integration.

## Offline evidence

[Recorded fixture results](evaluations/ai-feed-offline-2026-09-29.jsonl) contain eight reconstructed cases at the exact candidate above: ordinary retrieval, mixed sources, generation, transformation, missing dates, empty output, unusable output, and seeded history. All expected outcomes and count reconciliation pass (8 tests, 119 assertions). Fixture time is frozen at September 27, 18:00 UTC; model `gpt-5-nano`, usage, and costs are mocked. These are not live qualification results.

The full local Rails suite ran 4,317 tests and 13,637 assertions with one independently reproduced baseline failure: `FeedSchedulerJobTest#test_.perform_now_should_generate_originals_at_multiple_configured_same-day_slots`. Local database tests use PostgreSQL 18 through PGlite because this environment cannot run native PostgreSQL as a non-root user. GitHub CI uses the normal database setup. All 18 JavaScript tests and RuboCop pass. Require green GitHub checks at the final PR heads before merging.

Every code PR received a fresh minimal-context review. Review findings were fixed and rechecked: rollback import markers, excluded-preview copy, history-deletion cache invalidation, unknown failed-request tool costs, reporting assertions, and actionable preview errors. A separate whole-stack review checked selection, non-AI behavior, preview isolation, import transactions, retries, and accounting.

See [evaluation contracts](ai-feed-evaluation.md) for identity/date rules, lifecycle owners, counters, cost completeness, and provider boundaries. No runtime source verification, prompt classifier, refill loop, model fallback, or new pricing framework was added.

## Live gate: #1856

Use a credentialed development checkout of the candidate and the intended exact feed model. Historical `gpt-5.6-luna` evidence does not qualify requested `gpt-6-luna`. The coding agent's model does not select the feed model.

The required batch is three declared cases, each invoked twice: `qualifying`, `mixed_sources`, and `generation`. Generation disables web search; transformation is covered offline and is not an extra automatic paid run. Each command below runs once, rolls back its isolated feed/history/usage, and never publishes:

```sh
export AI_EVAL_CREDENTIAL_ID='DEVELOPMENT_CREDENTIAL_ID'
export AI_EVAL_MODEL='EXACT_MODEL_ID'
AI_EVAL_OUTPUT_DIR="/tmp/ai-feed-$(date -u +%F)"
mkdir -p "$AI_EVAL_OUTPUT_DIR"
AI_EVAL_CASE=qualifying bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/qualifying-1.json"
AI_EVAL_CASE=qualifying bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/qualifying-2.json"
AI_EVAL_CASE=mixed_sources bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/mixed_sources-1.json"
AI_EVAL_CASE=mixed_sources bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/mixed_sources-2.json"
AI_EVAL_CASE=generation bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/generation-1.json"
AI_EVAL_CASE=generation bin/rails runner script/evaluate_ai_feed.rb > "$AI_EVAL_OUTPUT_DIR/generation-2.json"
```

Review every selected result for usefulness, prompt adherence, formatting, and source support when retrieval is requested. Save sanitized outputs and pass/fail/pending notes; do not infer reliability from six runs. Repeat the same batch on a different UTC date, with unchanged code/prompts/model. Keep #1856 open until both dates are qualified; preserve partial evidence instead of retrying or changing models automatically.

## Shipping gate: #1857

After qualification, coordinate the existing deployment process: stop queues and finish/terminate old work; verify only the designated legacy AI records, previews, and pending jobs are cleared; deploy the complete qualified stack; verify fresh retrieval/generation feeds and preserved non-AI behavior; resume queues. Coordinate staging auto-deployment before merging. No merge, paid call, queue change, record reset, or deployment was performed during this offline implementation.
