# Claude Code remote environment (prebuilt dev container)

Claude Code on the web runs each session in a fresh Anthropic-managed VM. The base
image ships Ruby 3.1–3.3 only, but this project needs Ruby 4.0.3, so installing the
toolchain from scratch every session is slow. Instead we keep a **prebuilt dev
image** in GitHub Container Registry (GHCR) and run Rails inside it.

Replacing the VM's base image isn't supported, but Docker is available and **pulled
images are saved in the cached environment snapshot**, so each new session has the
image on disk without re-pulling. That gives us a reusable, cached image without
reinstalling dependencies each time.

## How the pieces fit together

| Piece | Where | Role |
| :--- | :--- | :--- |
| `Dockerfile.dev` | repo | Defines the dev image: Ruby 4.0.3 + gems + Node + yarn modules. |
| `.github/workflows/build-dev-image.yml` | repo | Builds the image and pushes it to `ghcr.io/dreikanter/f2-dev` on dependency changes (or on demand). |
| `compose.yaml` | repo | The dev stack: `app` (the image) + `db` (postgres:18). |
| Environment **setup script** | Claude web UI | Starts dockerd and `docker pull`s the image. Its result is cached into the environment snapshot. |
| `.claude/hooks/session-start.sh` | repo | Per session: starts dockerd, `docker compose up -d`, prepares the test DB. |

The setup script runs **once** per environment cache (re-runs roughly weekly or when
you edit it); the session-start hook runs **every** session. The image must be pulled
in the setup script for it to land in the cached snapshot — the hook only starts
containers from it.

## One-time setup

### 1. Publish the image

Merge this branch to `main`. The `Build dev image` workflow builds `Dockerfile.dev`
and pushes `ghcr.io/dreikanter/f2-dev:latest`. To build before merging, trigger the
workflow manually from the Actions tab (**Run workflow** → your branch).

After deps change later, the workflow rebuilds automatically when `Dockerfile.dev`,
`Gemfile.lock`, `package.json`, or `yarn.lock` change on `main`.

### 2. Make the package public

GHCR packages are private by default. Once the first build finishes, open the package
at `https://github.com/users/dreikanter/packages/container/f2-dev/settings` and set
**Visibility → Public**. A public image needs no auth in the sandbox.

> Prefer to keep it private? See [Private image](#private-image-alternative) below.

### 3. Add the environment setup script

In the Claude web UI, edit your environment and paste this into the **Setup script**
field (Network access must be **Trusted** or higher — `ghcr.io` is in the Trusted
allowlist):

```bash
#!/bin/bash
set -euo pipefail

# Start the Docker daemon (the init script fails on a ulimit call in this sandbox).
if ! docker info >/dev/null 2>&1; then
  nohup dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi

# Pull the prebuilt dev image so it's baked into the cached environment snapshot.
docker pull ghcr.io/dreikanter/f2-dev:latest
```

That's it. Start a fresh session and the session-start hook brings up the stack.

## Working in a session

The stack is already up (the hook ran `docker compose up -d`). Run Rails commands
inside the `app` container:

```bash
docker compose exec app bin/rails test
docker compose exec app bin/rails console
docker compose exec app bin/rubocop -f github
docker compose exec app bin/rails db:migrate
```

Rails server (port 3000 is published from the container):

```bash
docker compose exec app bin/rails server -b 0.0.0.0
```

Inspect the stack:

```bash
docker compose ps
docker compose logs app
```

## Updating the image

When gems or node modules change, the CI workflow rebuilds `:latest` on merge to
`main`. To refresh an already-cached environment immediately, re-run the setup script
(edit and save it in the UI, or start a session in an environment whose cache has
expired) so it pulls the new `:latest`.

## Local container usage

The same stack works locally without GHCR — Compose builds the image from
`Dockerfile.dev`:

```bash
docker compose up -d --build
docker compose exec app bin/rails test
```

(Day-to-day local dev can still use mise + native binstubs; the container is optional
locally.)

## Private image (alternative)

To keep `f2-dev` private:

1. Skip step 2 (leave the package private).
2. Create a GitHub token with `read:packages` scope (classic) or **Packages: read**
   (fine-grained), and add it as a `GHCR_TOKEN` environment variable in the Claude
   environment settings.
3. Add a login line before the pull in the setup script:

   ```bash
   echo "$GHCR_TOKEN" | docker login ghcr.io -u dreikanter --password-stdin
   docker pull ghcr.io/dreikanter/f2-dev:latest
   ```

Environment variables are visible to anyone who can edit the environment, so treat the
token accordingly.

## Troubleshooting

- **Daemon won't start:** check `/tmp/dockerd.log`. Start it by hand with
  `nohup dockerd >/tmp/dockerd.log 2>&1 &`. Use `dockerd` directly — `service docker
  start` fails on a `ulimit` permission error in the sandbox.
- **Image re-pulls every session:** the setup script isn't pulling it (only setup-script
  output is cached, not the session-start hook). Confirm step 3.
- **`pull access denied` / `denied`:** the package is private and unauthenticated. Make
  it public (step 2) or configure the token (private-image section).
- **DB connection refused:** the `db` service may still be starting. `docker compose up
  -d` waits for its healthcheck; re-run `docker compose exec app bin/rails db:test:prepare`.
