# AI usage reports

`LlmUsageReport` reads RubyLLM usage rows attributed through `LlmChat`.
Each SDK attempt is counted once, including failed attempts and multiple calls
within one chat. Requested model names, chat outcomes, and message token totals
do not replace the SDK's recorded model, status, tokens, or costs.

```ruby
LlmUsageReport.for_event(refresh_event).totals
LlmUsageReport.for_feed(feed).totals_for_periods
LlmUsageReport.for_credential(credential).totals_for_periods
LlmUsageReport.for_feed(feed, period: start_time...end_time).totals
```

Day, week, and month mean rolling 24-hour, 7-day, and 30-day windows ending at
`now`. Explicit ranges support calendar periods. Both use usage timestamps.
Feed totals include saved-feed previews; credential totals also include unsaved
previews and usage across feeds.

Costs are USD decimals. `known_cost` sums available costs; `total_cost` is `nil`
when any included row lacks a cost, and `incomplete?` marks that condition.
Known zero costs remain zero. Event snapshots convert totals to cents.

Reports cover retained SDK data. Interrupted requests may have no usage row.
Pruning a chat removes its usage from reports and event details; existing event
summary snapshots retain their original values. These reports are not a billing
ledger. External web-search accounting remains in `WebSearchUsage`.

## Previous accounting data

The old `llm_usages` table and model are removed. Stored records are discarded,
not migrated into RubyLLM usage, and their `LlmUsage` event references are deleted.
RubyLLM chats, messages, usage, external web-search accounting, and existing event
summary snapshots are preserved.

Rollback recreates an empty table; discarded records and references are not restored.
