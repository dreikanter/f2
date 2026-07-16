# Application metrics

## Feed refresh queue

### `feeder_feed_refresh_jobs_ready`

Number of `FeedRefreshJob` executions currently waiting in Solid Queue's ready queue.

A brief increase is expected when several feeds become due at the same schedule boundary. This metric shows the size of that burst, but not whether it is causing a practical delay.

### `feeder_feed_refresh_oldest_ready_age_seconds`

Age, in seconds, of the oldest `FeedRefreshJob` waiting in the ready queue. The value is `0` when no feed refresh is waiting.

This is the primary signal for deciding whether synchronized feed schedules need to be staggered:

- A high ready count with a low age means workers are draining the burst quickly.
- A growing age means feed refreshes are waiting and may delay other jobs in the shared queue.
- Repeated multi-minute peaks around schedule boundaries are evidence that staggering may be worth implementing.

Compare these metrics with `feeder_jobs_ready`, which includes every job type. If the global queue grows while the feed-refresh queue does not, feed scheduling is not the cause.

Both metrics are global gauges without feed or user labels. They are sampled by the process configured with `METRICS_GAUGES` and appear after the next metrics flush.
