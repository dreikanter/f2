# Notes for `/speckit-plan`: Profile output contracts and dedup identity

**Status**: Background for the plan phase. Not part of the spec proper. These
are implementation-level contracts that emerged in spec discussions but are
deliberately kept out of `spec.md` because they don't constrain user behavior
— they constrain how profiles are written. The plan phase should turn these
into concrete data-model and stage-class contracts.

**Parent docs**:
- [`spec.md`](../spec.md) — particularly FR-015 to FR-020.
- [`../../../docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md`](../../../docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md)
  — defines the three-stage pipeline and the `FeedEntry` shape.

## 1. Required post fields (every profile, AI-backed or not)

The Normalizer stage of every profile MUST produce a Post draft (or, upstream,
a `FeedEntry`) carrying:

| Field             | Type          | Notes |
|-------------------|---------------|-------|
| `title`           | string        | May be empty when the source has no title concept. |
| `body`            | string (rich) | The main content shown in the FreeFeed post body. |
| `supplementary`   | string?       | Optional content that goes into a comment on the published post. Used when the body is a summary and the original content is longer, OR when the source has supplementary material that's worth preserving but doesn't belong in the headline. |
| `images`          | string[]      | URLs the publisher can fetch and attach. Order matters. |
| `source_url`      | string        | Canonical link back to the original post. |
| `published_at`    | timestamp     | When the source post was published (source-side, not when Feeder saw it). |
| `uid`             | string        | Stable per-post dedup identifier. See §2. |

Visual fidelity to FreeFeed's rendering is **not** required in early
revisions. The structural shape is what matters: body, comments,
attachments — the pieces the publisher chooses among at publish time.

## 2. Dedup identifier (`uid`) policy

Each profile MUST derive `uid` deterministically from the source so that
running the same fetch twice produces the same `uid` for the same source
items. This is what FR-020 means by "the profile is responsible for deriving
a stable per-post identifier." Users never see or configure this.

Examples by profile type:

- **RSS / Atom**: the entry's `<guid>` element; fall back to `<link>` when
  `<guid>` is absent. (This is what the current code does for the `rss`
  profile.)
- **YouTube channel**: the video ID.
- **Twitter-via-AI-search**: the tweet's status URL (or the numeric status
  ID extracted from it).
- **AI-from-website**: trickier — the profile chooses a strategy that's
  stable for *its* source domain. Common shapes: canonical URL of the
  source page; canonical URL plus a stable content hash; an explicit
  per-item permalink the AI is instructed to extract. The profile MUST
  document its choice and MUST ensure the chosen identifier is stable
  across reasonable source mutations (e.g., minor edits to a blog post
  shouldn't generate a new `uid`).

Dedup happens in the surrounding workflow, not in stages: after the
processor returns `FeedEntry` instances, the workflow filters out any whose
`uid` already exists for this feed and only normalizes + publishes the
fresh ones. Stages stay pure.

## 3. AI profile output structure

AI-backed profiles use the `LlmClient` (parent spec phase 3). The client
enforces structured output via the provider's structured-output mechanism
(Anthropic forced tool use; OpenAI `response_format: json_schema`; etc. —
the client abstracts the mechanism).

The profile's `*_config` carries:

- A **prompt template** (system + user instructions) that wraps any
  feed-supplied parameters.
- An **output schema** matching the fields in §1. The schema is fixed by
  the profile, not the feed. Users supply *content* (e.g., a refinement
  query or a target URL) — not structure.

The schema MUST include the fields in §1, with reasonable per-profile
defaults (e.g., a Twitter profile sets `images` to empty when the tweet has
no media). The output is schema-validated by the client before any
downstream stage sees it. Validation failures fail the run with no post
published (parent spec, *Failure semantics*).

## 4. Preview generation

Preview rendering uses the same Loader → Processor → Normalizer chain as a
scheduled run, with two differences:

- **Bounded**: fetch and render only the first 2–5 items the processor
  produces. Profiles MAY support a `preview: true` hint to short-circuit
  expensive loader paths (e.g., an AI loader can ask the model for 5 items
  instead of 25).
- **Non-persistent**: nothing is saved to the database. `FeedEntry` and
  `Post` are constructed in memory and rendered.

For AI profiles, preview generation **does** spend tokens, since it
exercises the same LLM stages as a real run. This is expected and is
disclosed to the user once at the AI-option pick step (spec FR-022). The
preview's `LlmUsage` row is written like any other run's, attributed to the
not-yet-saved feed via a placeholder mechanism the plan phase will define
(options: a "preview" feed_id sentinel, or attribution to the user with
`feed_id = null`).

## 5. Implications for `FeedEntry` and `Post` shape

The parent spec already states `FeedEntry` carries `uid`, `published_at`,
and `raw_data`. The fields in §1 above MUST be representable somewhere
in the `FeedEntry` → `Post` path. Most likely:

- `FeedEntry.raw_data` carries source-shaped data per profile.
- `Post` (the publishable shape) carries the structured fields in §1.
- The Normalizer is the seam that maps `FeedEntry.raw_data` → `Post` fields.

The plan phase should confirm `Post` already has — or grow to have —
the fields in §1, including the `supplementary` field for overflow content
to be posted as a comment.

## 6. Open implementation questions for `/speckit-plan`

- Should the `output_schema` for AI profiles be expressed as JSON Schema
  Draft 7, Draft 2020-12, or a Ruby DSL? Parent spec defers this; preview
  + structured output is the forcing function.
- How is preview attribution recorded in `LlmUsage` when no `feed_id`
  exists yet? Options: sentinel value, nullable `feed_id` with a
  `purpose: preview` column, in-memory only with no row written.
- Where does the "save anyway after preview failure" path persist the
  feed when the loader/normalizer never produced a valid item? Likely:
  feed is saved in `state: pending_first_fetch`, and the first scheduled
  run is treated as the real validation.
- For AI-from-website with content-hash-based `uid`: what's the canonical
  text to hash? (Visible page text? Article body extracted by Readability?
  AI-extracted body?) Affects stability across minor source edits.
