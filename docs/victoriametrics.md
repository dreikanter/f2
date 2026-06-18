# VictoriaMetrics on Staging

Staging runs VictoriaMetrics as a Kamal accessory (`config/deploy.staging.yml`) with its built-in web UI (vmui). It collects metrics from two directions:

- **Scrape:** VM pulls host OS metrics (CPU, memory, disk, network) from the `node-exporter` accessory, per `config/victoriametrics/scrape.yml`.
- **Push:** the app sends its own `feeder_*` metrics (counters and gauges, including PostgreSQL sizes) to VM's import endpoint on the configured flush interval — 60 seconds on staging. See `app/services/metrics.rb` and `config/initializers/metrics.rb`.

VM is bound to localhost on the server. There are two ways to reach vmui:

- **Tailnet (recommended):** `https://f2-metrics.<your-tailnet>.ts.net/vmui`,
  served by the `tailscale` accessory — see `docs/deployment-tailscale.md`.
- **SSH tunnel** (fallback, no tailnet needed):

  ```
  ssh -L 8428:127.0.0.1:8428 dev.fffeeder.com
  ```

  Then open http://localhost:8428/vmui.

## App push configuration

The push side is controlled by app env vars (set under `env:` in the deploy config, applied by a regular `bin/kamal deploy` — no accessory reboot involved):

| Variable | Default | Purpose |
|---|---|---|
| `METRICS_URL` | unset | VM import endpoint. Unset means metrics are a complete no-op (dev, test). |
| `METRICS_FLUSH_INTERVAL` | `15` | Seconds between pushes. Each app process runs a flusher thread on this interval; gauge blocks (the DB queries) execute only at flush time, while counters accumulate in memory and cost nothing extra. |
| `METRICS_USERNAME` / `METRICS_PASSWORD` | unset | Basic auth for the import endpoint, if it's ever exposed beyond the private network. |
| `METRICS_INSTANCE` | `host:pid` | Override for the `instance` label on counter series. |
| `METRICS_GAUGES` | unset | Register the DB-sampled gauges in this process. Set on the web role only, so a single process samples them instead of every process repeating the same queries. Counters are unaffected and push from everywhere. |

Staging sets `METRICS_URL` and `METRICS_FLUSH_INTERVAL: "60"` globally (the sampled gauges move slowly, so a 60s push loses no visible resolution), plus `METRICS_GAUGES` on the web role; everything else uses defaults. The flush interval is the cheapest lever if the gauges ever get expensive — the charts just get coarser resolution.

One consequence of web-only gauges: if Puma is down, gauge series stop while counters keep flowing from the workers.

## Dashboards

Predefined dashboards live in `config/victoriametrics/dashboards/` as JSON files. Each file becomes its own tab on vmui's Dashboards page; the file's `title` field is the tab label. The accessory mounts each file individually under `files:` and points vmui at the directory with `-vmui.customDashboardsPath`.

To add a dashboard:

1. Create the JSON file in `config/victoriametrics/dashboards/`.
2. Add a matching mount line to the `victoriametrics` accessory in `config/deploy.staging.yml`:

   ```yaml
   files:
     - config/victoriametrics/dashboards/<name>.json:/etc/victoriametrics/dashboards/<name>.json
   ```

3. Merge, then reboot the accessory (below).

Editing an existing dashboard is the same minus step 2.

## Applying changes

Dashboard and scrape config changes do **not** ship with `bin/kamal deploy` — accessories are managed separately. After merging, run from an up-to-date `main` checkout:

```
bin/kamal accessory reboot victoriametrics -d staging
```

Kamal uploads the mounted files from your local working tree, so make sure you're on the commit you want to ship. The reboot recreates the container with fresh files and flags.

What requires a reboot and what doesn't:

| Change | VM reboot needed? |
|---|---|
| App pushes a new `feeder_*` metric | No — appears on the next flush after the app deploy |
| Dashboard JSON added or edited | Yes — vmui loads dashboards once at startup |
| `scrape.yml` edited | Yes — the file only reaches the host on reboot |

New series have no backfill: charts for a newly added metric start at the moment it first arrives, and panels referencing it are empty for earlier time ranges. That's expected.

## Safety notes

- Metrics history survives reboots — it lives in the `vmdata` volume on the host.
- The reboot causes a few seconds of downtime. App pushes during that window fail gracefully (logged, never raised) and node-exporter data has a small gap; both recover on their own.
- To tear the whole thing down: `bin/kamal accessory remove victoriametrics -d staging` and unset `METRICS_URL`.
