# Optional feed scheduling

**Status**: Implemented

Scheduling is a capability of a feed profile, not an implicit property of every feed.

Each `FeedProfile::PROFILES` entry declares `scheduled: true` or `scheduled: false` explicitly.
The registry flag is the single predicate used by feed validation and automatic schedule creation.
It supersedes feature-specific flags such as the proposed webhook `push: true` flag for deciding
whether a feed participates in periodic refreshes.

This contract supersedes the scheduling-specific parts of the webhook design in
[`006-webhook-publication`](../006-webhook-publication/spec.md), especially its proposed
`push: true` scheduling predicate and schedule-less self-healing workaround. The webhook profile
should instead declare `scheduled: false` when that branch is rebased.

## Behavior

- A scheduled profile requires a cron expression when the feed is enabled.
- Enabling a scheduled feed creates its initial `FeedSchedule`.
- An unscheduled profile does not require a cron expression and automatic lifecycle paths do not
  create a `FeedSchedule` for it.
- `Feed.due` includes only enabled feeds with an existing, non-null `next_run_at` that is due.
  A missing schedule or a schedule without a date is not an implicit due date.
- `FeedSchedulerJob#refresh?` checks the profile capability before reading or updating its schedule.
  An unscheduled feed is ignored even if a stale due schedule exists.
- If a scheduled feed's row disappears after it was selected as due, the existing recovery branch
  may recreate it; this is a race recovery path, not schedule-less discovery.

All profiles present when this contract was introduced are explicitly scheduled. A future webhook
profile should declare `scheduled: false`; its separate ingestion behavior does not need a generic
`push` registry flag for scheduling decisions.
