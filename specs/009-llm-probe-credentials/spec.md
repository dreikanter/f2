# Move the LLM probes onto credential records

**Date**: 2026-08-15 |
**Status**: Implemented in #1261.

**Related**: [`007-search-credentials`](../007-search-credentials/spec.md) ·
[`llm-provider-qualification`](../../docs/llm-provider-qualification.md) ·
[`search-provider-verification`](../../docs/search-provider-verification.md) ·
Issues/PRs: #1258 (the search probes this copies), #1260 (this design's ticket),
#1261 (the implementation)

The LLM capability probes read raw API keys from the process environment while everything else in
the app reads them from credential records. This is the record of why that moved and how the open
questions were settled.

## Why

- **One way to hold a key.** Every other part of the app reads provider keys from credential
  records: encrypted at rest, owned by a user, lifecycle-managed, revocable. The probes were the
  last place a key arrived as a process-wide environment variable, which meant a second answer to
  "where do keys live" and a second place to leak one.
- **The probe reconfigured what the app already configures.** `LlmCapabilityProbe::Provider` built
  its own `RubyLLM.context` per provider, with its own `env_key`, its own `api_base` default and
  its own `ruby_llm_provider` mapping — all of which `LlmProvider#configure` already did for
  production, down to Moonshot's `openai_use_system_role` flag, kept in step by a comment and a
  test. Two configuration paths mean a probe can pass while production fails, which is the one
  thing a qualification gate must not do.
- **Deployment carried the cost.** The keys had to be threaded through `deploy.staging.yml`, the
  staging workflow and `docs/deployment-setup.md` before a probe could run anywhere but a laptop.

## What changed

| Concern | Before | After |
| --- | --- | --- |
| Key source | `ENV["ANTHROPIC_API_KEY"]` etc. | `AiCredential` named after the probe |
| Provider config | `LlmCapabilityProbe::Provider` subclasses | `AiCredential#chat` |
| Owner | none (process-wide) | the user who pressed Run |
| Missing key | skip event: "no API key in environment" | skip event naming the credential to create |

The probe resolves `AiCredential` by name — `LlmCapabilityProbe.credential_name(provider)`, e.g.
"Anthropic Probe" — on the launching user's account, the way the search probes resolve theirs.
`ApplicationJob.runnable_arguments` hands the job the authenticated user, and because display
names are unique per `[user_id, provider]` the name resolves to exactly one record with no
tie-break to invent.

**Chat construction moved onto the credential rather than being copied into the probe.** The plan
was for `Runner` to call `credential.ruby_llm_context` and re-derive the provider key and
model-existence rule itself. Doing that would have left two assemblers of the same chat, which is
the defect this change exists to remove. `AiCredential#chat` is now the only one, used by both
`LlmClient#invoke_provider` and the probe, so the drift the old `configure` comment warned about
is no longer expressible.

The `models` check reads the listing through `LlmClient#available_models` — the call the
credential validation job makes — so a pass also proves the credential can be validated.

## How the open questions were settled

- **Qualifying a provider that is not wired yet.** Environment keys allowed probing a provider
  absent from `LlmProvider`'s registry; a credential cannot exist for one. Accepted as the cost:
  register the provider first. A registry entry is a row, not a feature — nothing reaches the
  model picker until `LlmModelCapability` gains a row, which is exactly what a passing probe
  earns. This is the one behavior genuinely given up.
- **`script/llm_capability_probe.rb`.** Kept, with a `--user` flag, rather than retired. Retiring
  was the smaller surface, but it is the documented way to probe a one-off pair or a subset of
  checks, and keeping it costs one option.
- **Usage accounting.** Probe runs write no `LlmUsage` rows. The search probe records a
  `WebSearchUsage` row per billed query, and the same "a real user's key is being spent" argument
  applies — but LLM usage is feed-run accounting: its `purpose` enum has no probe value and its
  rows hang off a feed. Recording probe traffic there is a schema change that deserves its own
  argument, and unlike a search query, where one request is one billable unit, honest rows would
  need per-call token totals from every check. The probe's cost is reported in the run's own
  events instead; `docs/llm-provider-qualification.md` says so rather than leaving it silent.

## Out of scope

The checks themselves. This changed where the key comes from, not what is verified; the
`models`/`plain`/`system_prompt`/`schema`/`client_tools` set is unchanged.

One adjacent simplification became available and was deliberately not taken: with managed
credentials in hand, `CannedWebSearch` could be replaced by the real search tool backed by a
`SearchCredential`. That trades a hermetic check for a more faithful one and should be argued on
its own merits, not smuggled in with a key-source refactor.
