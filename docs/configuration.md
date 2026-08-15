# Configuration

This app keeps configuration in a few layers. The goal is to keep deploy behavior in git, keep real secret values out of git, and avoid passing every application secret by hand during deploy.

## Structure

- **Kamal deploy config** → chooses destination, hosts, containers, env var names
- **Kamal secrets** → tells Kamal where to read secret values from locally (local machine holds *the few* real secrets needed to deploy)
- **Rails credentials** → encrypted *application-level* secrets committed to git

## Configuration sources

### `config/deploy.yml`

Base Kamal config shared by all destinations.

Defines the service, image repository, registry, builder architecture, shared env var names, and aliases.

### `config/deploy.staging.yml`

Staging deploy config.

Defines staging hosts, roles, proxy host, PostgreSQL accessory, and non-secret staging env vars.

### `config/deploy.production.yml`

Production deploy config.

Defines production hosts, roles, proxy host, PostgreSQL accessory, and non-secret production env vars.

### `.kamal/secrets-common`

Shared Kamal secret pointers.

Example: maps `KAMAL_REGISTRY_PASSWORD` to local `GHCR_TOKEN` so Kamal can push/pull images from GHCR.

### `.kamal/secrets.staging`

Staging Kamal secret pointers.

Maps runtime secrets to local values, including the staging database password and Rails credentials key.

### `.kamal/secrets.production`

Production Kamal secret pointers.

Maps runtime secrets to local values, including the production database password and Rails credentials key.

### `config/credentials/staging.yml.enc`

Encrypted staging Rails credentials.

Committed to git. Rails decrypts it at boot using `RAILS_MASTER_KEY`.

### `config/credentials/production.yml.enc`

Encrypted production Rails credentials.

Committed to git. Rails decrypts it at boot using `RAILS_MASTER_KEY`.

### `config/credentials/*.key`

Local-only Rails credential keys.

Not committed. Kamal reads the right key and passes it to the container as `RAILS_MASTER_KEY`.

## Environment variable naming

When a value differs per environment, the environment goes **last**, as a suffix:

```text
POSTGRES_PASSWORD_STAGING
POSTGRES_PASSWORD_PRODUCTION
RAILS_MASTER_KEY_STAGING
SSH_PRIVATE_KEY_STAGING
```

The base name stays stable, so every variant of a value sorts and groups
together and the environment reads as a qualifier rather than a namespace.
Names with no suffix (`GHCR_TOKEN`, `IMGPROXY_KEY`) are shared by all
environments.

The suffix only exists where several environments' values sit side by side —
GitHub Actions secrets and local shell exports. Inside a container the app sees
the plain name: `.kamal/secrets.staging` maps `POSTGRES_PASSWORD_STAGING` to
`POSTGRES_PASSWORD`.

## Why both Kamal secrets and Rails credentials?

Kamal secrets answer: **where does deploy read secret values from?**

Rails credentials answer: **where does the app read application secrets from?**

This keeps the deploy-time secret list short. Kamal passes a few secrets, including `RAILS_MASTER_KEY`; Rails uses that key to decrypt the rest.
