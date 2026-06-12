# VictoriaMetrics on Staging

Staging runs VictoriaMetrics as a Kamal accessory (`config/deploy.staging.yml`) with its built-in web UI (vmui). It collects metrics from two directions:

- **Scrape:** VM pulls host OS metrics (CPU, memory, disk, network) from the `node-exporter` accessory, per `config/victoriametrics/scrape.yml`.
- **Push:** the app sends its own `feeder_*` metrics (counters and gauges, including PostgreSQL sizes) to VM's import endpoint every ~15 seconds. See `app/services/metrics.rb` and `config/initializers/metrics.rb`.

VM is bound to localhost on the server, so view the UI through an SSH tunnel:

```
ssh -L 8428:127.0.0.1:8428 dev.fffeeder.com
```

Then open http://localhost:8428/vmui.

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
