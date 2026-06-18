# Deployment: Tailscale access to vmui

VictoriaMetrics runs as a localhost-bound Kamal accessory (see
`docs/victoriametrics.md`), so it isn't reachable from the network. The
`tailscale` accessory (`config/deploy.staging.yml`) publishes its web UI on our
tailnet, so you get a stable HTTPS URL without exposing any public port.

`tailscale serve` is the whole edge: it terminates TLS with an automatic
Tailscale-issued cert and reverse-proxies to `f2-victoriametrics:8428` over the
Kamal network. There is no public listening port, no Let's Encrypt/Cloudflare
cert dance, and no password — access is gated by tailnet membership and ACLs.

## How it fits together

- `config/tailscale/serve.json` — the serve config: HTTPS on the node's
  MagicDNS name (`${TS_CERT_DOMAIN}`, expanded by the container) → proxy to VM.
- The accessory runs in **userspace mode** (`TS_USERSPACE=true`), so it needs no
  `NET_ADMIN`/`/dev/net/tun`.
- State persists in the `tsdata` volume (`/var/lib/tailscale`) so the node keeps
  its identity across reboots.

## One-time setup

1. In the **Tailscale admin console**, enable **MagicDNS** and **HTTPS
   Certificates** (Settings → DNS). `serve` needs these for the cert.
2. Create an **auth key** (Settings → Keys): **reusable** and **non-ephemeral**
   so reboots re-auth without losing the node (an OAuth client key also works).
3. Store it as the `TS_AUTHKEY` GitHub Actions secret, and for local deploys:

   ```bash
   export TS_AUTHKEY='tskey-auth-...'
   ```

4. (Optional) Pin the image: `config/deploy.staging.yml` uses
   `tailscale/tailscale:stable` — replace with a specific `vX.Y.Z` to match the
   repo's pin-everything convention.

## Deploy

Accessories deploy separately from the app:

```bash
bin/kamal accessory boot tailscale -d staging      # first time
bin/kamal accessory reboot tailscale -d staging    # after serve.json changes
```

## Access

Open `https://f2-metrics.<your-tailnet>.ts.net/vmui` from any device on the
tailnet. (The exact host is `TS_HOSTNAME` + your tailnet's MagicDNS suffix.)

## Notes

- `serve` keeps this **private to the tailnet**. Do not switch it to `funnel`
  unless you intend to publish it to the public internet.
- Auth keys expire (~90 days by default); the reusable/non-ephemeral key plus
  the state volume mean you only revisit this if the key itself is rotated.
- Tear down with `bin/kamal accessory remove tailscale -d staging` (also delete
  the node in the admin console).
