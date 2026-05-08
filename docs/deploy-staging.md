# Staging Deployment (Hetzner + Kamal)

Deploys Feeder to a fresh Hetzner Cloud server as a staging environment. Functionally close to production, but with an ephemeral database that can be dropped and reseeded at will.

- **Domain:** `dev.fffeeder.com`
- **Database name:** `f2_staging`
- **Rails env:** `staging` (a dedicated environment that inherits production settings)
- **Kamal destination:** `staging` (config in `config/deploy.staging.yml`)

## Prerequisites

This guide assumes the following are already in place on the `main` branch:

- `config/environments/staging.rb` exists (typically loads `production.rb` and overrides what differs).
- `config/credentials/staging.yml.enc` and `config/credentials/staging.key` (the latter gitignored).
- `config/deploy.staging.yml` and `config/deploy.production.yml` exist as Kamal destinations.
- `.kamal/secrets.staging` exists alongside the default `.kamal/secrets`.

## 1. Provision the Hetzner server

1. Create a Cloud server (Ubuntu 24.04 LTS, CX22 is enough to start; pick a larger instance type when running heavier workloads).
2. Attach an SSH key during creation so the server is reachable as `root` without a password.
3. Note the public IPv4 address.
4. (Optional) Enable Hetzner Cloud Firewall and allow inbound `22`, `80`, `443` only.

Verify SSH access:

```bash
ssh root@<hetzner-ip> "uname -a"
```

No further server setup is required — `bin/kamal setup -d staging` (step 5) installs Docker on first run via the bootstrap step:

```bash
bin/kamal server bootstrap -d staging   # runs implicitly during `setup`; can also be run on its own
```

## 2. Point DNS at the server

Create an `A` record:

```
dev.fffeeder.com.  A  <hetzner-ip>
```

Confirm propagation before running `kamal setup` — Let's Encrypt cert issuance via kamal-proxy needs the domain to resolve to the server. Check with `dig`:

```bash
dig +short dev.fffeeder.com
# Expected output: <hetzner-ip>
```

Or poll until it matches:

```bash
until [ "$(dig +short dev.fffeeder.com)" = "<hetzner-ip>" ]; do sleep 5; done
```

## 3. Update `config/deploy.staging.yml`

Replace the placeholders:

```yaml
servers:
  web:
    - <hetzner-ip>
  jobs:
    hosts:
      - <hetzner-ip>
    cmd: bin/jobs

proxy:
  ssl: true
  host: dev.fffeeder.com

accessories:
  db:
    image: postgres:18
    host: <hetzner-ip>
    # ...
```

Keep `RAILS_ENV: staging`. The app connects to the Kamal PostgreSQL accessory through `config/database.yml`, using the `POSTGRES_PASSWORD` secret. Commit the changes:

```bash
git add config/deploy.staging.yml
git commit -m "Configure staging server"
```

## 4. Prepare secrets

Kamal reads `.kamal/secrets.staging` automatically when invoked with `-d staging`. It pulls from the local environment, so export before running any deploy command:

```bash
export GITHUB_TOKEN=<ghcr-pat-with-read:packages>      # KAMAL_REGISTRY_PASSWORD
export POSTGRES_PASSWORD=<generate-a-strong-password>  # used by the db accessory
```

`RAILS_MASTER_KEY` resolves from `config/credentials/staging.key` (gitignored) via the secrets file — no env var needed when that file is present locally. To override (e.g. on CI), `export RAILS_MASTER_KEY=<staging-key>` before deploying.

Note: Freefeed API keys are configured per-user inside the app (Access Tokens). Staging only posts to whatever Freefeed accounts are entered there — there is no shared production key in the deploy.

## 5. First deploy

From the workstation, on the branch to ship:

```bash
bin/kamal setup -d staging
```

This installs Docker on the server, boots the PostgreSQL accessory, pulls/builds the image, runs migrations, and starts web + jobs behind kamal-proxy with a Let's Encrypt cert for `dev.fffeeder.com`.

Subsequent deploys:

```bash
bin/kamal deploy -d staging
```

Verify:

```bash
curl -I https://dev.fffeeder.com/up
bin/kamal app details -d staging
```

## 6. Rebuilding the database

Because staging data is disposable, the fastest reset drops and recreates the schema from inside the app container:

```bash
bin/kamal app exec --reuse "bin/rails db:drop db:create db:migrate" -d staging
bin/kamal app exec --reuse "bin/rails db:seed" -d staging
```

For a truly clean slate (including the Postgres data volume):

```bash
bin/kamal accessory stop db -d staging
bin/kamal accessory remove db -d staging   # prompts; this deletes the data volume
bin/kamal accessory boot db -d staging
bin/kamal app exec --reuse "bin/rails db:prepare" -d staging
```

## 7. Day-to-day

All commands take `-d staging` to target this destination:

```bash
bin/kamal logs -d staging                  # tail web logs
bin/kamal logs -r jobs -d staging          # tail SolidQueue worker
bin/kamal console -d staging               # rails console (alias)
bin/kamal shell -d staging                 # bash inside app container (alias)
bin/kamal dbc -d staging                   # rails dbconsole (alias)
bin/kamal rollback <version> -d staging    # roll back to a prior image
```
