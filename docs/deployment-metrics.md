# Deployment: metrics proxy

VictoriaMetrics runs as a Kamal **accessory** (see `docs/victoriametrics.md`):
it's stateful (the `vmdata` volume), it's the private push target the app reaches
by container name, and it mounts the scrape/dashboard files. All of that is a
natural fit for the accessory model, and accessories stay bound to localhost.

The one thing an accessory can't do is get a public HTTPS host — accessories
aren't routed through kamal-proxy. So the public edge is a separate, tiny
standalone app: a Caddy reverse proxy that kamal-proxy routes (giving it a
Let's Encrypt cert for `metrics.fffeeder.com`), enforces HTTP basic auth, and
forwards to the VM accessory over the Kamal network.

This mirrors the imgproxy setup (`docs/deployment-imgproxy.md`) — a standalone
app for the public edge — but here it fronts a stateful accessory rather than
replacing it. VM has no auth of its own (vmui and the full read/write/delete API
would be wide open), so the proxy's basic auth is what keeps the endpoint safe;
unlike imgproxy, which is safe to expose because it only serves signed URLs.

## Config layout

- `config/deploy.metrics.yml` — Kamal config for the standalone proxy app.
- `config/metrics-proxy/Dockerfile` — thin `FROM caddy:<tag>` wrapper that bakes
  in the Caddyfile.
- `config/metrics-proxy/Caddyfile` — basic auth + reverse proxy to
  `f2-victoriametrics:8428`; serves `/up` unauthenticated for kamal-proxy's
  health check.
- `.github/workflows/deploy-metrics.yml` — on-demand (`workflow_dispatch`) deploy.

## Secret

Only one secret is needed: the basic-auth password, stored **bcrypt-hashed** so
the stored value is never the plaintext password. The username isn't sensitive
and lives in `config/deploy.metrics.yml` as a clear env var (`METRICS_USER`,
default `admin`).

Generate the hash:

```bash
docker run --rm caddy:2.10-alpine caddy hash-password --plaintext <password>
```

Store the result as the GitHub Actions repository secret `METRICS_PASSWORD_HASH`
(the deploy workflow passes it through). For local deploys, export it first:

```bash
export METRICS_PASSWORD_HASH='<hash>'
```

`.kamal/secrets-common` reads it, so it's available to the proxy app without a
per-destination secrets file.

## DNS and Cloudflare

Same shape as imgproxy — two records with different jobs:

| Record | Cloudflare | Points at | Used for |
| --- | --- | --- | --- |
| Deploy host (`dev.fffeeder.com`) | DNS-only (grey) | server IP | Kamal SSH + Let's Encrypt |
| `metrics.fffeeder.com` | Proxied (orange) | the origin | public endpoint |

The deploy host (`servers.web.hosts`) must resolve **directly** to the server so
SSH and the ACME challenge reach the origin, not Cloudflare. It must also be the
**same host as the VM accessory** so the proxy can reach `f2-victoriametrics`
over the Kamal docker network. `proxy.host` is the public name.

### Let's Encrypt behind Cloudflare

kamal-proxy issues the cert for `metrics.fffeeder.com`, but the ACME challenge
fails if the record is already proxied. Either deploy with the record **DNS-only
(grey)** first so the cert is issued, then switch to **proxied (orange)** with
SSL mode **Full (strict)** (renewals need the same grey window); or install a
**Cloudflare Origin Certificate** on kamal-proxy and skip Let's Encrypt. See
`docs/deployment-imgproxy.md` for the same trade-off in more detail.

## Deploy

VM and the proxy change rarely, so deploys are on demand — the workflow does not
run on push. Trigger the **Deploy metrics proxy** workflow from the Actions tab,
or deploy locally:

```bash
bin/kamal deploy -c config/deploy.metrics.yml
```

The first time on a fresh host, run `setup` instead of `deploy`.

## Upgrade

Bump the tag in `config/metrics-proxy/Dockerfile` and redeploy.

## Verify

```bash
# Health endpoint bypasses auth (kamal-proxy checks /up).
curl -I https://metrics.fffeeder.com/up                 # 200

# Unauthenticated UI requests are rejected.
curl -I https://metrics.fffeeder.com/vmui               # 401

# With credentials, vmui loads.
curl -I -u admin:<password> https://metrics.fffeeder.com/vmui   # 200
```
