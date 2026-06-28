# uid Integrity Implementation Plan (Track 1 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI-feed post uids stable across runs by deriving them from the item's source permalink (system-normalized) instead of trusting a model-supplied `uid`.

**Architecture:** Introduce a pure, unit-tested `Uid::Resolver` that turns an AI-extracted item into a stable uid by normalizing its `source_url` permalink (lowercase scheme/host, drop fragment, strip tracking query params, canonicalize trailing slash). `PassthroughProcessor` calls it instead of reading `item["uid"]`. Items without a usable deep-link permalink are dropped, exactly as today — so this is a strict improvement with no behaviour change for digests yet.

**Tech Stack:** Ruby (mise-managed), Rails edge, Minitest + FactoryBot, RuboCop.

**Spec:** [`spec.md`](./spec.md) §3 (uid contract). This plan delivers the permalink-normalization core of §3. The **digest/period-keyed fallback** and the **explicit model regime signal** are deferred to Track 4 (Single AI profile), where the output schema and system prompt change.

## Global Constraints

- Ruby/Node via mise; run binstubs directly in local dev: `bin/rails test`, `bin/rubocop -f github`. (Remote Claude Code env: prefix with `docker compose exec app`.)
- Minitest with FactoryBot; create test data with factories, lazy (memoized helper methods, not eager `setup`).
- Unit-test naming: `test "#method should ..."`.
- Always end source files with a trailing newline.
- Fix RuboCop violations after each change: `bin/rubocop -f github`.
- Report handled exceptions via `Rails.error.report(e, context: {...})`.
- Atomic commits, short imperative subjects ≤ 50 chars. No CHANGELOG entry — this change is internal (no user-facing behaviour change).

## File Structure

- `app/services/uid/resolver.rb` — new. Pure service: `Uid::Resolver.call(item, clock:) -> String | nil`. One responsibility: derive a stable uid string from an item, or `nil` when no usable permalink exists.
- `app/services/processor/passthrough_processor.rb` — modify. Replace the `item["uid"]` read with a `Uid::Resolver.call` call; keep the existing blank-uid drop.
- `test/services/uid/resolver_test.rb` — new. Unit tests for the resolver (no DB).
- `test/services/processor/passthrough_processor_test.rb` — new or modify. Pipeline-level tests, including run-twice uid stability.

---

### Task 1: `Uid::Resolver`

**Files:**
- Create: `app/services/uid/resolver.rb`
- Test: `test/services/uid/resolver_test.rb`

**Interfaces:**
- Consumes: nothing (pure; `item` is a `Hash` with string or symbol keys, `clock` responds to `#to_date`).
- Produces: `Uid::Resolver.call(item, clock:) -> String | nil`. Returns a normalized URL string for a usable deep-link `source_url`; returns `nil` when `source_url` is missing, unparseable, non-HTTP, or a bare homepage.

- [ ] **Step 1: Write the failing test**

Create `test/services/uid/resolver_test.rb`:

```ruby
require "test_helper"

class Uid::ResolverTest < ActiveSupport::TestCase
  def clock = Time.utc(2026, 6, 29, 10, 0, 0)

  test "#call should normalize a deep-link permalink into a uid" do
    item = { "source_url" => "https://Example.COM/Blog/Post-1/" }
    assert_equal "https://example.com/Blog/Post-1", Uid::Resolver.call(item, clock: clock)
  end

  test "#call should strip tracking params and fragments" do
    item = { "source_url" => "https://example.com/p/9?utm_source=rss&id=7&fbclid=abc#top" }
    assert_equal "https://example.com/p/9?id=7", Uid::Resolver.call(item, clock: clock)
  end

  test "#call should drop a query that is only tracking params" do
    item = { "source_url" => "https://example.com/p/9?utm_source=rss" }
    assert_equal "https://example.com/p/9", Uid::Resolver.call(item, clock: clock)
  end

  test "#call should accept symbol keys" do
    item = { source_url: "https://example.com/a" }
    assert_equal "https://example.com/a", Uid::Resolver.call(item, clock: clock)
  end

  test "#call should return nil for a bare homepage" do
    assert_nil Uid::Resolver.call({ "source_url" => "https://example.com/" }, clock: clock)
  end

  test "#call should return nil when source_url is missing" do
    assert_nil Uid::Resolver.call({ "body" => "hi" }, clock: clock)
  end

  test "#call should return nil for a non-http or malformed url" do
    assert_nil Uid::Resolver.call({ "source_url" => "ftp://example.com/x" }, clock: clock)
    assert_nil Uid::Resolver.call({ "source_url" => "not a url" }, clock: clock)
  end

  test "#call should be identical across runs for the same permalink" do
    item = { "source_url" => "https://example.com/post/1" }
    first = Uid::Resolver.call(item, clock: clock)
    second = Uid::Resolver.call(item, clock: Time.utc(2026, 7, 1))
    assert_equal first, second
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/uid/resolver_test.rb`
Expected: FAIL — `NameError: uninitialized constant Uid` (resolver doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `app/services/uid/resolver.rb`:

```ruby
module Uid
  # Derives a stable post uid from an AI-extracted item, anchored to source
  # identity rather than generated content (summaries change every run, so a
  # content hash would break dedup). A usable deep-link permalink becomes a
  # normalized-URL uid that matches across runs; an item without one returns
  # nil and is dropped upstream.
  #
  # The digest/period-keyed fallback and the model's explicit regime signal
  # arrive with the single-AI-profile work (Track 4); `clock` is threaded now
  # so that addition needs no signature change.
  class Resolver
    TRACKING_PARAM = /\A(utm_|fbclid\z|gclid\z|mc_)/

    def self.call(item, clock:)
      new(item, clock).call
    end

    def initialize(item, clock)
      @item = item.is_a?(Hash) ? item : {}
      @clock = clock
    end

    def call
      uri = deep_link
      uri && normalize(uri)
    end

    private

    attr_reader :item, :clock

    def deep_link
      raw = (item["source_url"] || item[:source_url]).to_s.strip
      return if raw.empty?

      uri = URI.parse(raw)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return if uri.path.delete_suffix("/").empty? && uri.query.nil? # bare homepage

      uri
    rescue URI::InvalidURIError
      nil
    end

    def normalize(uri)
      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
      uri.fragment = nil
      uri.query = clean_query(uri.query)
      uri.path = uri.path.delete_suffix("/") unless uri.path == "/"
      uri.to_s
    end

    def clean_query(query)
      return if query.nil?

      kept = URI.decode_www_form(query).reject { |key, _| key.match?(TRACKING_PARAM) }
      kept.empty? ? nil : URI.encode_www_form(kept)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/uid/resolver_test.rb`
Expected: PASS (8 runs, 0 failures).

- [ ] **Step 5: Lint**

Run: `bin/rubocop -f github app/services/uid/resolver.rb test/services/uid/resolver_test.rb`
Expected: no offenses (fix any reported before committing).

- [ ] **Step 6: Commit**

```bash
git add app/services/uid/resolver.rb test/services/uid/resolver_test.rb
git commit -m "Add Uid::Resolver for permalink-normalized uids"
```

---

### Task 2: Wire `Uid::Resolver` into `PassthroughProcessor`

**Files:**
- Modify: `app/services/processor/passthrough_processor.rb`
- Test: `test/services/processor/passthrough_processor_test.rb`

**Interfaces:**
- Consumes: `Uid::Resolver.call(item, clock:)` from Task 1.
- Produces: no signature change — `Processor::PassthroughProcessor.new(feed, raw_data).process` still returns a `Processor::Result`; entries now carry resolver-derived uids and items without a usable permalink are dropped.

- [ ] **Step 1: Write the failing test**

Create (or extend) `test/services/processor/passthrough_processor_test.rb`:

```ruby
require "test_helper"

class Processor::PassthroughProcessorTest < ActiveSupport::TestCase
  def feed = @feed ||= create(:feed)

  def process(items) = Processor::PassthroughProcessor.new(feed, items).process

  test "#process should derive a normalized permalink uid and ignore model-supplied uid" do
    items = [{ "uid" => "ephemeral-123", "source_url" => "https://Example.com/post/1/?utm_source=x", "body" => "hi" }]

    entries = process(items).entries

    assert_equal 1, entries.size
    assert_equal "https://example.com/post/1", entries.first.uid
  end

  test "#process should produce identical uids across separate runs" do
    items = [{ "source_url" => "https://example.com/a", "body" => "x" }]

    first = process(items).entries.first.uid
    second = process(items).entries.first.uid

    assert_equal first, second
  end

  test "#process should drop items without a usable permalink" do
    items = [{ "source_url" => "https://example.com/", "body" => "homepage only" }]

    assert_empty process(items).entries
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/processor/passthrough_processor_test.rb`
Expected: FAIL on the first test — uid is still `"ephemeral-123"` (the old `item["uid"]` read), not the normalized permalink.

- [ ] **Step 3: Update the processor**

In `app/services/processor/passthrough_processor.rb`, replace the uid line inside the `filter_map` block. Change:

```ruby
        uid = item["uid"].presence || item[:uid].presence
        next if uid.blank?
```

to:

```ruby
        uid = Uid::Resolver.call(item, clock: Time.current)
        next if uid.blank?
```

(The `next if uid.blank?` guard stays — it now drops items the resolver couldn't anchor to a permalink, preserving today's "drop unidentifiable item" behaviour.)

- [ ] **Step 4: Run the processor tests to verify they pass**

Run: `bin/rails test test/services/processor/passthrough_processor_test.rb`
Expected: PASS (3 runs, 0 failures).

- [ ] **Step 5: Run the broader suite to catch regressions**

Run: `bin/rails test test/services/`
Expected: PASS. If a pre-existing AI-pipeline test asserted on a model-supplied `uid`, update it to assert the resolver-derived permalink uid (the model-supplied `uid` is intentionally ignored now).

- [ ] **Step 6: Lint**

Run: `bin/rubocop -f github app/services/processor/passthrough_processor.rb test/services/processor/passthrough_processor_test.rb`
Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
git add app/services/processor/passthrough_processor.rb test/services/processor/passthrough_processor_test.rb
git commit -m "Derive passthrough uids via Uid::Resolver"
```

---

## Self-Review

- **Spec coverage (§3):** permalink-normalized, system-derived uid ✓ (Task 1); model-supplied uid no longer trusted ✓ (Task 2); run-twice-identical assertion ✓ (Task 1 Step 1 + Task 2 Step 1). Deferred-by-design and called out at the top: digest/period-keyed fallback and the explicit model regime signal → Track 4. "Ephemeral-uid rejection" from §3 is satisfied **by construction** here — the model no longer mints the uid, so an unstable uid can't occur; an item without a stable permalink is dropped rather than admitted.
- **Placeholders:** none — every step has full code or an exact command.
- **Type consistency:** `Uid::Resolver.call(item, clock:)` returns `String | nil`; the processor drops on `nil` via the retained `next if uid.blank?`. `clock` is consumed in Task 1 (threaded for Track 4) though unused by the current permalink path — intentional, documented in the class comment.
