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

Existing `llm_usages` records are discarded, not migrated into RubyLLM usage.
The data migration deletes those rows and their `LlmUsage` event references.
RubyLLM chats, messages, usage, and external web-search accounting are preserved,
as are existing event summary snapshots.

The deletion is permanent: rolling back the migration does not restore the
records. The empty table and its model remain until the separate accounting
cleanup removes them.
