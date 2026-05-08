# Deployment Setup (Kamal)

Feeder is deployed with Kamal destinations. Always pass an explicit destination so commands target the right hosts, domains, credentials, and database.

```bash
bin/kamal deploy -d staging
bin/kamal deploy -d production
```

`config/deploy.yml` has `require_destination: true`, so Kamal refuses destination-less deploys.

## Destinations

| Destination | Domain | Rails env | Database | Config |
| --- | --- | --- | --- | --- |
| `staging` | `dev.fffeeder.com` | `staging` | `f2_staging` | `config/deploy.staging.yml` |
| `production` | `fffeeder.com` | `production` | `f2_production` | `config/deploy.production.yml` |

`www.fffeeder.com` is redirected to `fffeeder.com` by Cloudflare, so Kamal and Rails only need to accept the apex production host.

The image is currently built for `amd64`, so deployment hosts should be x86_64/amd64 servers.

## Config layout

- `config/deploy.yml` — shared Kamal config: service name, image, registry, shared secrets, aliases, asset path, builder.
- `config/deploy.staging.yml` — staging servers, proxy host, PostgreSQL accessory, and clear env vars.
- `config/deploy.production.yml` — production servers, proxy host, PostgreSQL accessory, and clear env vars.
- `.kamal/secrets-common` — shared secret definitions used by all destinations.
- `.kamal/secrets.staging` — staging-only secret definitions.
- `.kamal/secrets.production` — production-only secret definitions.

Kamal loads destination config by merging the base file with the destination file:

```bash
bin/kamal config -d staging     # deploy.yml + deploy.staging.yml
bin/kamal config -d production  # deploy.yml + deploy.production.yml
```

Run those commands after changing deploy config to catch syntax or merge issues.

## Hosts and DNS

The server names in `servers` and `accessories.db.host` must be reachable over SSH from your workstation. Domain names are fine as long as they resolve directly to the server.

For staging:

```yaml
servers:
  web:
    - dev.fffeeder.com

proxy:
  ssl: true
  host: dev.fffeeder.com
```

For production:

```yaml
servers:
  web:
    - fffeeder.com

proxy:
  ssl: true
  host: fffeeder.com
```

Before the first setup, confirm DNS points to the server so Let's Encrypt can issue certificates:

```bash
dig +short dev.fffeeder.com
dig +short fffeeder.com
```

If a domain is proxied by Cloudflare and SSH does not work through it, use a direct DNS name or the server IP in `servers` and `accessories.db.host`. Keep `proxy.host` set to the public app domain.

Confirm the host architecture matches the configured builder architecture:

```bash
ssh root@dev.fffeeder.com "uname -m"   # expected: x86_64
ssh root@fffeeder.com "uname -m"       # expected: x86_64
```

## Secrets

Kamal destination deploys read:

```text
.kamal/secrets-common
.kamal/secrets.<destination>  # only if present
```

This project keeps the GHCR token mapping in `.kamal/secrets-common`:

```bash
KAMAL_REGISTRY_PASSWORD=$GHCR_TOKEN
```

Destination-specific files provide the database password and Rails credentials key. Each destination reads its own shell variable so both can stay exported at once without crossing values:

```bash
# .kamal/secrets.staging
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_STAGING
RAILS_MASTER_KEY=$(cat config/credentials/staging.key)

# .kamal/secrets.production
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_PRODUCTION
RAILS_MASTER_KEY=$(cat config/credentials/production.key)
```

Before deploying, make sure these are available locally:

```bash
export GHCR_TOKEN=<ghcr-token>
export POSTGRES_PASSWORD_STAGING=<staging-database-password>
export POSTGRES_PASSWORD_PRODUCTION=<production-database-password>
```

And make sure the destination credentials key exists locally:

```text
config/credentials/staging.key
config/credentials/production.key
```

The `.key` files are gitignored. Store and share them through the team password manager.

## Database

Each destination runs a Kamal PostgreSQL accessory named `db`. PostgreSQL 18 stores versioned data under `/var/lib/postgresql`, so the accessory mounts `data:/var/lib/postgresql` instead of mounting the `data` subdirectory directly.

The app connects through `config/database.yml` using:

- username: `f2`
- password: `POSTGRES_PASSWORD`
- host: `f2-db`
- database name based on `RAILS_ENV`

Do not put the database password in `DATABASE_URL`. Keep it in Kamal secrets.

## Preflight

Before deploying, verify the local environment and target host:

```bash
git pull

test -n "$GHCR_TOKEN" && echo "GHCR_TOKEN set"
test -n "$POSTGRES_PASSWORD_STAGING" && echo "POSTGRES_PASSWORD_STAGING set"
test -f config/credentials/staging.key

ssh root@dev.fffeeder.com "uname -m"   # expected: x86_64
bin/kamal config -d staging
```

For production, use `$POSTGRES_PASSWORD_PRODUCTION`, `config/credentials/production.key`, `root@fffeeder.com`, and `bin/kamal config -d production`.

## First deploy

For a new server, run setup once:

```bash
bin/kamal setup -d staging
bin/kamal setup -d production
```

`setup` bootstraps Docker, starts accessories, deploys the app, runs migrations, and configures kamal-proxy with HTTPS.

Subsequent deploys:

```bash
bin/kamal deploy -d staging
bin/kamal deploy -d production
```

Verify:

```bash
curl -I https://dev.fffeeder.com/up
curl -I https://fffeeder.com/up
bin/kamal app details -d staging
bin/kamal app details -d production
bin/kamal accessory details db -d staging
bin/kamal accessory details db -d production
```

Expected result:

- `/up` returns `200`
- web and jobs containers are running
- the `db` accessory is running

## Staging database reset

Staging data is disposable. To reset the schema inside the app container:

```bash
bin/kamal app exec --reuse "bin/rails db:drop db:create db:migrate" -d staging
bin/kamal app exec --reuse "bin/rails db:seed" -d staging
```

For a clean slate including the Postgres data volume:

```bash
bin/kamal accessory stop db -d staging
bin/kamal accessory remove db -d staging   # prompts; this deletes the data volume
bin/kamal accessory boot db -d staging
bin/kamal app exec --reuse "bin/rails db:prepare" -d staging
```

## Honeybadger

Staging and production read Honeybadger configuration from encrypted Rails credentials:

```yaml
honeybadger:
  api_key: your_environment_key
```

Edit credentials with:

```bash
EDITOR="code --wait" bin/rails credentials:edit --environment staging
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

If staging does not have a valid key, the app still runs, but logs will include Honeybadger `403` warnings.

## Troubleshooting

If deploy fails or the target does not become healthy, check the app and accessory logs:

```bash
bin/kamal app logs -d staging --lines 200
bin/kamal accessory logs db -d staging --lines 100
bin/kamal app details -d staging
bin/kamal accessory details db -d staging
```

If the app container exited before Kamal can find it, inspect containers directly on the host:

```bash
ssh root@dev.fffeeder.com 'docker ps -a --filter label=service=f2 --filter label=destination=staging'
ssh root@dev.fffeeder.com 'docker logs --timestamps --tail 200 <container-id-or-name>'
```

Common issues:

- `flag needs an argument: 'p' in -p` during `docker login` — `GHCR_TOKEN` is not set locally.
- `could not translate host name "f2-db"` — the PostgreSQL accessory is not running or failed to join the Docker network.
- PostgreSQL 18 complains about `/var/lib/postgresql/data` — recreate the accessory after pulling the config that mounts `data:/var/lib/postgresql`.
- `/up` returns `403` with `Blocked hosts` — Rails host authorization is blocking the health check; `/up` should be excluded in production config.
- platform mismatch — confirm the server is `x86_64` and `builder.arch` is `amd64`.

## Useful commands

All commands should include `-d staging` or `-d production`.

```bash
bin/kamal logs -d staging
bin/kamal logs -r jobs -d staging
bin/kamal console -d staging
bin/kamal shell -d staging
bin/kamal dbc -d staging
bin/kamal rollback <version> -d staging
```
