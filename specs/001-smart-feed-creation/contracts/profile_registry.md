# Contract: Enriched `FeedProfile` Registry Entry

**Audience**: stage-class authors and operators adding new profiles.
**Status**: planning-time (Phase 1 design output).

Each entry in `FeedProfile::PROFILES` is a `Hash` matching the schema below. Schema-validated in CI via `test/support/feed_profile_validator.rb`; the test suite fails loudly if a profile is malformed. (The registry is a frozen constant, so a runtime boot check would be wasted work.)

## Hash schema

```text
{
  display_name:        String,           # required, ≤ 80 chars, shown in candidate chooser
  description:         String,           # required, ≤ 200 chars, shown in candidate chooser tooltip
  input_shape:         Symbol,           # required, one of :url, :handle, :query, :any
  depends_on_ai:       Boolean,          # required; true if any stage's class uses LlmClient
  scheduled:           Boolean,          # required; true when feeds use cron-backed periodic refresh
  matcher:             String,           # required, fully-qualified class name (must subclass ProfileMatcher::Base)
  parameter_schema:    Hash,             # required, JSON Schema Draft 2020-12 describing the feed's `params` JSONB
  loader:              StageEntry,       # required (see below)
  processor:           StageEntry,       # required
  normalizer:          StageEntry,       # required
  title_extractor:     String?           # optional, fully-qualified class name (TitleExtractor::Base subclass) — used during detection to pre-fill the feed name
  output_schema:       Hash?             # required IFF any stage uses LlmClient; JSON Schema for the structured LLM response
}

StageEntry:
{
  class:  String,                        # fully-qualified class name (must be loadable at boot)
  config: Hash                           # frozen at registration; passed to the stage class constructor
}
```

For LLM-using stages, `StageEntry.config` carries the LLM-specific bits:

```text
{
  model:           String,               # e.g. "claude-opus-4-7"
  prompt_template: String,               # `{key}` substitution from feed.params; or ERB if `prompt_format: "erb"`
  prompt_format:   String?,              # default "simple"; alternative "erb"
  output_schema:   Hash,                 # JSON Schema for this stage's response (mirrors top-level output_schema for normalizer-only AI use)
  tools:           [String]?             # provider-side server tool names (e.g. ["web_search", "web_fetch"])
}
```

## Constraints

1. **No two profiles** may have the same `key` (the hash key).
2. The matcher's `input_shape` MUST equal the entry's `input_shape`. Boot validation enforces this.
3. **Ranking** is determined at detection time by:
   - **Specificity**: a profile is more specific than another if its matcher's `match_specificity` (an integer the matcher declares) is higher.
   - **AI penalty**: profiles with `depends_on_ai: true` rank lower than any non-AI profile that matched the same input.
4. `parameter_schema` MUST validate the `params` JSON the feed will store. Required fields surface as required form fields.
5. `output_schema` MUST include the universal post fields (`title`, `body`, `supplementary?`, `images[]`, `source_url`, `published_at`, `uid`) — see [`../notes/profile-contracts.md`](../notes/profile-contracts.md).
6. `scheduled` MUST be explicit. When false, the feed does not require a cron expression and must not acquire a `FeedSchedule` through enablement or scheduler recovery.

## Adding a new profile

1. Write the matcher class (subclass `ProfileMatcher::Base`, declare `input_shape`, declare `match_specificity`, implement `match?(input)`).
2. Write or reuse loader / processor / normalizer classes.
3. Add the entry to `FeedProfile::PROFILES` and explicitly set `scheduled`.
4. Add a profile fixture in `test/fixtures/profiles/` and a profile-level test exercising `parameter_schema` validity, end-to-end `FeedRefreshWorkflow` for one sample item, and (if AI-backed) an `LlmClient` stub.
5. CI fails if `FeedProfileValidator.validate!` rejects the new entry.

## Examples

The two existing profiles (`rss`, `xkcd`) get migrated to this shape as part of the registry-refactor task. The first three new profiles (`llm_website_extractor`, `llm_handle_search`, `llm_web_search`) ship in successive tasks.
