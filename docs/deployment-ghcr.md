# Kamal and GitHub Container Registry

This project uses Kamal to build, publish, pull, and run Docker images. GitHub is only involved as the container image registry through GitHub Container Registry, also known as GHCR.

## Image location

The shared Kamal config in `config/deploy.yml` sets:

```yaml
image: dreikanter/f2

registry:
  server: ghcr.io
  username: dreikanter
  password:
    - KAMAL_REGISTRY_PASSWORD
```

That makes the app image:

```text
ghcr.io/dreikanter/f2
```

Kamal tags each build and pushes it to that image repository.

## Credentials

Kamal reads the registry password from `KAMAL_REGISTRY_PASSWORD`. In this repo, `.kamal/secrets-common` maps it to the local `GHCR_TOKEN` environment variable:

```bash
KAMAL_REGISTRY_PASSWORD=$GHCR_TOKEN
```

Before deploying, export a GitHub token that can push and pull packages:

```bash
export GHCR_TOKEN=<github-container-registry-token>
```

The token usually needs:

- `write:packages` to push images
- `read:packages` to pull images
- `delete:packages` only if you plan to remove images manually

## Deployment flow

A typical deploy looks like this:

```bash
bin/kamal deploy -d staging
bin/kamal deploy -d production
```

During deployment, Kamal:

1. Builds the Docker image from the app code.
2. Logs in to `ghcr.io` as `dreikanter` using `GHCR_TOKEN`.
3. Pushes the tagged image to `ghcr.io/dreikanter/f2`.
4. Connects to the deployment server over SSH.
5. Logs Docker on the server in to GHCR.
6. Pulls the same image onto the server.
7. Starts or replaces the app containers with the new image.

## What GitHub does and does not do

Kamal does not deploy from the GitHub source repository. It does not need GitHub Actions or direct access to the repo to deploy from your workstation.

GitHub's role here is just to store and serve the built Docker image:

```text
local build → ghcr.io/dreikanter/f2 → deployment server
```

If a deploy fails around registry login, push, or pull, check that `GHCR_TOKEN` is exported and has the right package permissions.
