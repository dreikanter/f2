# Deployment: imgproxy

[imgproxy](https://imgproxy.net) resizes post attachment images on the fly. It
runs as its own Kamal app, separate from the main Feeder deploy, and sits behind
Cloudflare so resized variants are cached at the edge.

It's a standalone app (not a Kamal accessory) because it needs its own public
HTTPS host. Accessories aren't routed through kamal-proxy, but a standalone app
is — so imgproxy gets a Let's Encrypt certificate and a clean host without any
extra port juggling.

## Config layout

- `config/deploy.imgproxy.yml` — Kamal config for the imgproxy app.
- `config/imgproxy/Dockerfile` — thin `FROM ghcr.io/imgproxy/imgproxy:<tag>`
  wrapper. imgproxy ships as a prebuilt public image, but Kamal always builds the
  service image, so this lets Kamal retag and push it to our registry.
- `.github/workflows/deploy-imgproxy.yml` — on-demand (`workflow_dispatch`) deploy.

## Secrets

imgproxy only serves **signed** URLs — unsigned requests get a `403`, so the
public endpoint can't be abused to resize arbitrary images. The signing key and
salt are shared by two sides:

- the imgproxy app, which verifies signatures, and
- the main app's web/jobs roles, which sign the URLs.

Because there is a single imgproxy instance, both read the same pair from
`.kamal/secrets-common` (`IMGPROXY_KEY`, `IMGPROXY_SALT`) rather than duplicating
them per destination.

Generate each value once (hex):

```bash
openssl rand -hex 64   # IMGPROXY_KEY
openssl rand -hex 64   # IMGPROXY_SALT
```

Store them as GitHub Actions repository secrets named `IMGPROXY_KEY` and
`IMGPROXY_SALT` (both the staging and imgproxy workflows pass them through). For
local deploys, export them first:

```bash
export IMGPROXY_KEY=<hex>
export IMGPROXY_SALT=<hex>
```

## DNS and Cloudflare

Two records with different jobs:

| Record | Cloudflare | Points at | Used for |
| --- | --- | --- | --- |
| Deploy host (`dev-origin.fffeeder.com`) | DNS-only (grey) | server IP | Kamal SSH + Let's Encrypt |
| `imgproxy.fffeeder.com` | Proxied (orange) | the origin | public CDN endpoint |

The deploy host (`servers.web.hosts`) is the box Kamal SSHes into and where
kamal-proxy runs the ACME challenge, so it must resolve **directly** to the
server. Don't use a Cloudflare-proxied name like `imgproxy.fffeeder.com` (or
`dev.fffeeder.com`) as the deploy host: it resolves to Cloudflare's IPs — SSH
(port 22) and the Let's Encrypt challenge would hit Cloudflare instead of the
origin and fail. `proxy.host` is set to `imgproxy.fffeeder.com` (the public
name); the deploy host is the shared grey origin record `dev-origin.fffeeder.com`.

To move imgproxy to its own server later without touching this config, give it a
dedicated grey origin record (e.g. `imgproxy-origin.fffeeder.com`), use that as
the deploy host, and CNAME the orange `imgproxy.fffeeder.com` to it. Then a move
is a single A-record IP change.

### Let's Encrypt behind Cloudflare

kamal-proxy issues a Let's Encrypt certificate for `imgproxy.fffeeder.com`, but
the ACME challenge fails if the record is already proxied (it lands on
Cloudflare). Two options:

- Deploy with the record **DNS-only (grey)** first so the cert is issued, then
  switch it to **proxied (orange)** with SSL mode **Full (strict)**. Renewals
  need the same grey window.
- Or skip Let's Encrypt and install a **Cloudflare Origin Certificate** on
  kamal-proxy (via Kamal's custom-cert secrets) with SSL mode **Full (strict)**.
  This avoids the renewal dance and is the better long-term setup.

## Deploy

imgproxy changes rarely, so deploys are on demand — the workflow does not run on
push. Trigger the **Deploy imgproxy** workflow from the Actions tab, or deploy
locally:

```bash
bin/kamal deploy -c config/deploy.imgproxy.yml
```

The first time on a fresh host, run `setup` instead of `deploy`.

## Upgrade

Bump the tag in `config/imgproxy/Dockerfile` and redeploy.

## Verify

```bash
# Health endpoint (kamal-proxy checks /health, not /up).
curl -I https://imgproxy.fffeeder.com/health   # 200

# An unsigned processing URL must be rejected.
curl -I "https://imgproxy.fffeeder.com/unsafe/rs:fill:100:100/plain/https://example.com/a.jpg"  # 403
```

A correctly signed URL returns the resized image. The app builds and signs these
URLs; see the application integration for how.
