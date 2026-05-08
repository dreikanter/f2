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

## Secrets

Kamal destination deploys read:

```text
.kamal/secrets-common
.kamal/secrets.<destination>  # only if present
```

This project keeps the GHCR token mapping in `.kamal/secrets-common`:

```bash
KAMAL_REGISTRY_PASSWORD=$GITHUB_TOKEN
```

Destination-specific files provide the database password and Rails credentials key:

```bash
# .kamal/secrets.staging
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
RAILS_MASTER_KEY=$(cat config/credentials/staging.key)

# .kamal/secrets.production
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
RAILS_MASTER_KEY=$(cat config/credentials/production.key)
```

Before deploying, make sure these are available locally:

```bash
export GITHUB_TOKEN=<ghcr-token>
export POSTGRES_PASSWORD=<database-password>
```

And make sure the destination credentials key exists locally:

```text
config/credentials/staging.key
config/credentials/production.key
```

The `.key` files are gitignored. Store and share them through the team password manager.

## Database

Each destination runs a Kamal PostgreSQL accessory named `db`.

The app connects through `config/database.yml` using:

- username: `f2`
- password: `POSTGRES_PASSWORD`
- host: `f2-db`
- database name based on `RAILS_ENV`

Do not put the database password in `DATABASE_URL`. Keep it in Kamal secrets.

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
```

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
