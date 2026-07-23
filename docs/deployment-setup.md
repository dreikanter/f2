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
| `production` | `app.fffeeder.com` | `production` | `f2_production` | `config/deploy.production.yml` |

`fffeeder.com` and `www.fffeeder.com` are redirected to `app.fffeeder.com` by Cloudflare, so Kamal and Rails only need to accept the `app` production host.

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
    - app-origin.fffeeder.com

proxy:
  ssl:
    certificate_pem: CERTIFICATE_PEM
    private_key_pem: PRIVATE_KEY_PEM
  host: app.fffeeder.com
```

Both destinations use the same split: a grey origin record as the SSH target and
a Cloudflare-proxied public name — see the origin certificate section below.

Before the first setup, confirm the origin records resolve straight to the servers:

```bash
dig +short dev-origin.fffeeder.com
dig +short app-origin.fffeeder.com
```

If a domain is proxied by Cloudflare and SSH does not work through it, use a direct DNS name or the server IP in `servers` and `accessories.db.host`. Keep `proxy.host` set to the public app domain.

Confirm the host architecture matches the configured builder architecture:

```bash
ssh root@dev-origin.fffeeder.com "uname -m"   # expected: x86_64
ssh root@app-origin.fffeeder.com "uname -m"   # expected: x86_64
```

## Cloudflare Origin Certificate

The public hosts (`dev.fffeeder.com`, `app.fffeeder.com`) are Cloudflare-proxied
(orange), so kamal-proxy can't get a Let's Encrypt certificate: the ACME
HTTP-01 challenge lands on Cloudflare, not the origin. Instead kamal-proxy
serves a **Cloudflare Origin Certificate** and Cloudflare runs in SSL mode
**Full (strict)**, keeping both hops (browser↔edge and edge↔origin) encrypted
and validated with no renewal dance.

This needs the deploy host split from the public host. Two DNS records per
destination:

| Record | Cloudflare | Used for |
| --- | --- | --- |
| `dev-origin.fffeeder.com` | DNS-only (grey) → staging server IP | Kamal SSH, accessories, cert install |
| `dev.fffeeder.com` | Proxied (orange) | staging `proxy.host` |
| `app-origin.fffeeder.com` | DNS-only (grey) → production server IP | Kamal SSH, accessories, cert install |
| `app.fffeeder.com` | Proxied (orange) | production `proxy.host` |

`servers.*` and `accessories.*.host` point at the grey record (Cloudflare proxies
only HTTP/S, so SSH must bypass it); `proxy.host`, `HOSTS`, and
`ACTION_MAILER_HOST` stay the public name (Cloudflare forwards the original Host
header, so host routing and Rails host authorization still match).

Setup:

1. Cloudflare → **SSL/TLS → Origin Server → Create Certificate**. Hostname
   `*.fffeeder.com` (covers both `dev` and `app`), validity 15 years. Keep the
   certificate (PEM) and private key blobs handy for the next step.
2. Provide the cert/key through the environment as multi-line PEM values —
   the same flow as `IMGPROXY_KEY` and friends. kamal-proxy reads them from the
   `CERTIFICATE_PEM` / `PRIVATE_KEY_PEM` secrets, which pull from
   `CF_ORIGIN_CERT` / `CF_ORIGIN_KEY` (see `.kamal/secrets.staging` and
   `.kamal/secrets.production`):
   - **CI:** add `CF_ORIGIN_CERT` and `CF_ORIGIN_KEY` as GitHub Actions
     repository secrets (paste the full PEM, including the BEGIN/END lines). The
     **Deploy Staging** and **Deploy Production** workflows pass them through.
   - **Local deploys:** export them first, reading from your saved files:

     ```bash
     export CF_ORIGIN_CERT="$(cat cf-origin.pem)"
     export CF_ORIGIN_KEY="$(cat cf-origin.key)"
     ```
3. Cloudflare → **SSL/TLS → Overview** → set mode **Full (strict)**, and make the
   public DNS records (`dev.fffeeder.com`, `app.fffeeder.com`) **Proxied
   (orange)**. Keep the `*-origin` records grey.
4. Deploy:

```bash
bin/kamal proxy reboot -d staging
bin/kamal deploy -d staging
```

Verify the origin actually serves the Cloudflare cert (bypassing the edge):

```bash
curl -kvI --resolve dev.fffeeder.com:443:<ORIGIN_IP> https://dev.fffeeder.com/up 2>&1 \
  | grep -i "issuer"   # CloudFlare Origin SSL Certificate Authority
```

The origin cert is trusted only by Cloudflare, so hitting the origin directly
shows a browser warning — expected, since real traffic flows through the proxy.

## Secrets

Kamal destination deploys read:

```text
.kamal/secrets-common
.kamal/secrets.<destination>  # only if present
```

This project keeps the GHCR token and the shared imgproxy signing key/salt in
`.kamal/secrets-common`:

```bash
KAMAL_REGISTRY_PASSWORD=$GHCR_TOKEN
IMGPROXY_KEY=$IMGPROXY_KEY
IMGPROXY_SALT=$IMGPROXY_SALT
```

The web and jobs roles use `IMGPROXY_KEY`/`IMGPROXY_SALT` to sign image URLs. The
imgproxy service that verifies them is deployed separately — see
[deployment-imgproxy.md](deployment-imgproxy.md).

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
export IMGPROXY_KEY=<imgproxy-signing-key>
export IMGPROXY_SALT=<imgproxy-signing-salt>
```

And make sure the destination credentials key exists locally:

```text
config/credentials/staging.key
config/credentials/production.key
```

The `.key` files are gitignored. Store and share them through the team password manager.

## Deploying from GitHub Actions

Both destinations can be deployed from the Actions tab. **Deploy Staging** also
runs on every push to the `staging` branch; **Deploy Production** is
`workflow_dispatch` only, so production deploys are always deliberate.

The workflows read these repository secrets:

| Secret | Used by | Purpose |
| --- | --- | --- |
| `GHCR_TOKEN` | both | GHCR login and `KAMAL_REGISTRY_PASSWORD` |
| `IMGPROXY_KEY` / `IMGPROXY_SALT` | both | imgproxy URL signing (required by `.kamal/secrets-common`) |
| `POSTGRES_PASSWORD_STAGING` | staging | staging database password |
| `POSTGRES_PASSWORD_PRODUCTION` | production | production database password |
| `RAILS_MASTER_KEY_STAGING` | staging | written to `config/credentials/staging.key` |
| `RAILS_MASTER_KEY_PRODUCTION` | production | written to `config/credentials/production.key` |
| `STAGING_SSH_PRIVATE_KEY` | staging | SSH key for `dev-origin.fffeeder.com` |
| `PRODUCTION_SSH_PRIVATE_KEY` | production | SSH key for `app-origin.fffeeder.com` |
| `CF_ORIGIN_CERT` / `CF_ORIGIN_KEY` | both | Cloudflare Origin Certificate for kamal-proxy |
| `ANTHROPIC_API_KEY` / `MOONSHOT_API_KEY` | staging | optional LLM keys for the capability probe job |

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

ssh root@dev-origin.fffeeder.com "uname -m"   # expected: x86_64
bin/kamal config -d staging
```

For production, use `$POSTGRES_PASSWORD_PRODUCTION`, `config/credentials/production.key`, `root@app-origin.fffeeder.com`, and `bin/kamal config -d production`.

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
curl -I https://app.fffeeder.com/up
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

Reported errors are tagged with the deployed git revision (`APP_REVISION`, set by
Kamal), so Honeybadger can group errors by release and show when each first
appeared. After every `bin/kamal deploy`, the `.kamal/hooks/post-deploy` hook
notifies Honeybadger of the new deploy by running `bin/rails honeybadger:notify_deploy`
inside the booted container. With no API key configured the notification is a no-op.

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
