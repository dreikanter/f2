---
name: verify
description: Launch and drive this app in a remote Claude Code environment to verify a change end-to-end in a real browser.
---

# Verifying F2 changes at the browser surface

The dev stack runs in Docker (see CLAUDE.md Tooling Notes). Everything below
assumes the remote environment where `docker compose` is already up.

## Launch

```sh
docker compose exec -d app bin/rails server -b 0.0.0.0   # app on host port 3000
docker compose exec -d app bin/jobs                      # SolidQueue worker — needed for
                                                         # feed identification/preview jobs
```

Log in as the seeded dev user: `test@example.com` / `password123`
(created by `db:seed`, which `db:prepare` runs).

Background `exec -d` processes die when the container restarts (e.g. on
session resume) — re-run both commands if port 3000 stops answering.

## Drive with Playwright

Use host Chromium: `playwright-core` + `executablePath: "/opt/pw-browsers/chromium"`.

**Critical gotcha:** the JS entrypoint (`app/javascript/tailwind.js`) statically
imports `flowbite` from cdn.jsdelivr.net. The sandboxed browser has no CDN
egress, so that one failed import kills the entire module graph — Turbo and
Stimulus never boot and forms fall back to full-page POSTs that render raw
turbo-stream XML. Fix: fetch the file once with host `curl` (which goes through
the agent proxy with its CA) and serve it via route interception:

```js
await page.route("**/flowbite.turbo.min.js", (r) =>
  r.fulfill({ path: "flowbite.turbo.min.js", contentType: "text/javascript" }));
```

esm.sh imports (tippy, date-fns) may keep failing — harmless, they're loaded
per-controller by stimulus-loading which catches the error (only datepicker/
tooltips break). Stub `fonts.googleapis.com` with empty CSS to cut noise.

## Feed URLs for detection flows

- `localhost`/private hosts are **SSRF-refused before the fetch** — they always
  yield the terminal "couldn't pull any posts" state, never a working feed.
  A local stub server is useless for the happy path.
- Working public feed reachable through the proxy:
  `https://github.com/rails/rails/releases.atom` (any GitHub releases.atom).
- Couldn't-reach (transient) state: an unresolvable host, e.g.
  `http://no-such-host-vfy.example/feed.xml`.
- A settled working identification is keyed by (user, canonical URL) — reusing
  a URL that already identified skips detection (and in edit, instantly
  confirms the source change). Use a fresh URL per detection scenario.
