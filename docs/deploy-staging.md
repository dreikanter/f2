# Staging Deployment (Hetzner + Kamal)

Deploys Feeder to a fresh Hetzner Cloud server as a staging environment. Functionally identical to production, but with an ephemeral database that can be dropped and reseeded at will.

- **Domain:** `dev.fffeeder.com`
- **Database name:** `f2_staging`
- **Rails env:** `production` (staging is just production with throwaway data)

## 1. Provision the Hetzner server

1. Create a Cloud server (Ubuntu 24.04 LTS, CX22 is enough to start; pick a larger instance type when running heavier workloads).
2. Attach an SSH key during creation so the server is reachable as `root` without a password.
3. Note the public IPv4 address.
4. (Optional) Enable Hetzner Cloud Firewall and allow inbound `22`, `80`, `443` only.

Verify SSH access:

```bash
ssh root@<hetzner-ip> "uname -a"
```

No further server setup is required — `bin/kamal setup` (step 5) installs Docker on first run via the bootstrap step:

```bash
bin/kamal server bootstrap   # runs implicitly during `setup`; can also be run on its own
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

## 3. Update `config/deploy.yml`

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

Keep `RAILS_ENV: production` and `DATABASE_URL=postgres://f2:password@f2-db:5432/f2_staging` (the password segment is a Kamal-internal placeholder; the real password comes from the `POSTGRES_PASSWORD` secret). Commit the changes:

```bash
git add config/deploy.yml
git commit -m "Configure staging server"
```

## 4. Prepare secrets

`kamal` reads `.kamal/secrets`, which pulls from the local environment. Export before running any deploy command:

```bash
export GITHUB_TOKEN=<ghcr-pat-with-read:packages>      # KAMAL_REGISTRY_PASSWORD
export POSTGRES_PASSWORD=<generate-a-strong-password>  # used by the db accessory
# RAILS_MASTER_KEY is read from config/master.key automatically
```

Notes:
- Use a **dedicated** `config/master.key` for staging when production credentials should not be decryptable on this box. Keep that key out of git; store it in a password manager.
- Freefeed API keys are configured per-user inside the app (Access Tokens). Staging only posts to whatever Freefeed accounts are entered there — there is no shared production key in the deploy.

## 5. First deploy

From the workstation, on the branch to ship:

```bash
bin/kamal setup
```

This installs Docker on the server, boots the PostgreSQL accessory, pulls/builds the image, runs migrations, and starts web + jobs behind kamal-proxy with a Let's Encrypt cert for `dev.fffeeder.com`.

Subsequent deploys:

```bash
bin/kamal deploy
```

Verify:

```bash
curl -I https://dev.fffeeder.com/up
bin/kamal app details
```

## 6. Seed test data

`db/seeds.rb` is gated on `Rails.env.development?`, so it does not run automatically on staging. Two options:

**Option A — quick and dirty (recommended for staging):** loosen the guard so staging can seed too.

```ruby
# db/seeds.rb
if Rails.env.development? || ENV["ALLOW_SEEDS"] == "1"
  # ...
end
```

Then run on the server:

```bash
bin/kamal app exec --reuse "env ALLOW_SEEDS=1 bin/rails db:seed"
```

**Option B — keep seeds dev-only**, and create staging fixtures via a dedicated rake task (e.g. `lib/tasks/staging.rake`) that builds the same fixture set:

```bash
bin/kamal app exec --reuse "bin/rails staging:seed"
```

## 7. Rebuilding the database

Because staging data is disposable, the fastest reset drops and recreates the schema from inside the app container:

```bash
bin/kamal app exec --reuse "bin/rails db:drop db:create db:migrate"
bin/kamal app exec --reuse "env ALLOW_SEEDS=1 bin/rails db:seed"
```

For a truly clean slate (including the Postgres data volume):

```bash
bin/kamal accessory stop db
bin/kamal accessory remove db        # prompts; this deletes the data volume
bin/kamal accessory boot db
bin/kamal app exec --reuse "bin/rails db:prepare"
```

## 8. Day-to-day

```bash
bin/kamal logs                  # tail web logs
bin/kamal logs -r jobs          # tail SolidQueue worker
bin/kamal console               # rails console (alias)
bin/kamal shell                 # bash inside app container (alias)
bin/kamal dbc                   # rails dbconsole (alias)
bin/kamal rollback <version>    # roll back to a prior image
```

## Checklist

- [ ] Hetzner server provisioned, SSH access works as `root`
- [ ] `dev.fffeeder.com` A record resolves to the server
- [ ] `config/deploy.yml` updated (server IPs + `proxy.host`)
- [ ] `GITHUB_TOKEN`, `POSTGRES_PASSWORD` exported; `config/master.key` present
- [ ] `bin/kamal setup` succeeded; `https://dev.fffeeder.com` serves the app
- [ ] DB seeded with test data
