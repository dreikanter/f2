# VictoriaLogs

Staging and production ship structured application and job logs to separate
[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) instances so they
can be queried by fields such as status, controller, job class, and level.
Three pieces work together:

- **App:** `rails_semantic_logger` makes the app emit one JSON object per log
  line to STDOUT (requests, app logs, and Solid Queue lifecycle). Configured in
  `config/environments/production.rb`, which `staging.rb` inherits. Scoped to
  the deployed environments only; local dev and tests keep Rails' default
  human-readable logger.
- **Vector** (`vector` accessory): reads the `f2-web` and `f2-jobs` container
  stdout through the Docker API and forwards the parsed JSON to VictoriaLogs
  over the private Kamal network. Config in `config/vector/vector.yaml`.
- **VictoriaLogs** (`vlogs` accessory): stores and serves the logs with a
  built-in web UI. Each destination has its own storage and two-day retention.

Both accessories are declared in `config/deploy.staging.yml` and
`config/deploy.production.yml`. There are no new secrets. VictoriaLogs is bound
to localhost and only reachable over the Kamal network or an SSH tunnel.

## Viewing the UI

VictoriaLogs is bound to localhost on the server, so reach the UI through an SSH
tunnel:

```
ssh -L 9428:127.0.0.1:9428 dev-origin.fffeeder.com   # staging
ssh -L 9428:127.0.0.1:9428 app-origin.fffeeder.com   # production
```

Run the command for the destination you want to inspect, then open
http://localhost:9428/select/vmui/.

## Querying

The UI takes [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/).
Because Vector hoists `semantic_logger`'s `payload` to the top level, request
and job fields are queryable directly:

```
level:ERROR
status:>=500
container_name:f2-jobs AND level:WARN
controller:FeedsController duration:>1000
```

`container_name` distinguishes web (`f2-web-*`) from jobs (`f2-jobs-*`), so
Solid Queue lines are easy to isolate.

## What gets logged

`semantic_logger` emits `message`, `timestamp`, `level`, `name`, and a `payload`
of structured fields. Vector maps `message`/`timestamp` to VictoriaLogs'
`_msg_field`/`_time_field` and streams by `container_name,level`. Non-JSON lines
(early boot, libraries that bypass the Rails logger) still arrive, with the raw
text kept as the message.

> Kamal names containers `<service>-<role>-<destination>-<version>`. Vector
> matches on the `f2-web` / `f2-jobs` prefixes, so it works in both destinations
> and across deploys. If the service or role names ever change, update
> `include_containers` in `config/vector/vector.yaml`.

## Applying changes

Like the VictoriaMetrics accessory, these are managed separately from
`bin/kamal deploy`. The app-side logging format ships with a normal deploy, but
the accessories and the Vector config do not. To deploy them to production
after merging, run from an up-to-date checkout:

```
bin/kamal accessory boot vlogs -d production
bin/kamal accessory boot vector -d production
```

Kamal uploads `config/vector/vector.yaml` from your local working tree, so make
sure you're on the commit you want to ship. To pick up an edited Vector config
later, reboot just that accessory:

```
bin/kamal accessory reboot vector -d production
```

Use `-d staging` instead for the staging accessories.

| Change | Accessory action |
|---|---|
| App starts logging a new field | None — appears on the next deploy |
| `config/vector/vector.yaml` edited | `reboot vector` |
| Retention or storage flags changed | `reboot vlogs` |

## Safety notes

- Log history survives reboots — it lives in the `data` volume on the host.
- Rebooting `vlogs` causes a short gap where Vector can't deliver. Vector buffers
  and retries, so recent lines catch up once it's back.
- Retention is two days (`-retentionPeriod=2d`); older logs drop automatically.
- The host's container logs are capped (`logging.max-size`/`max-file` in
  `config/deploy.yml`), so the json-file driver Vector reads from can't grow
  unbounded.
- To tear the whole thing down:
  `bin/kamal accessory remove vector -d production` and
  `bin/kamal accessory remove vlogs -d production`. The app keeps emitting JSON
  to STDOUT regardless; that's harmless with nothing collecting it.
