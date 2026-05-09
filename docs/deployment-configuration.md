# Deployment Configuration Map

Developer-facing deployment setup is split between committed config, local secret files, and local environment variables.

## Dependency chain

```text
bin/kamal
  → config/deploy.yml
    → config/deploy.<destination>.yml
    → .kamal/secrets-common
    → .kamal/secrets.<destination>
      → local environment variables
      → config/credentials/<destination>.key
    → config/credentials/<destination>.yml.enc
```

## Files

### `bin/kamal`

- **Committed:** yes
- **Format:** Ruby binstub
- **Purpose:** Runs the Kamal gem from this app's bundle.
- **Used when:** any Kamal command runs.

### `config/deploy.yml`

- **Committed:** yes
- **Format:** YAML
- **Purpose:** Base Kamal config shared by all destinations.
- **Contains:** service name, image name, GHCR registry settings, shared secret names, builder architecture, aliases.
- **Used when:** any Kamal deploy/build/config command runs.

### `config/deploy.staging.yml`

- **Committed:** yes
- **Format:** YAML
- **Purpose:** Staging destination config.
- **Contains:** staging hosts, roles, proxy host, PostgreSQL accessory, clear staging env vars.
- **Used when:** running Kamal with `-d staging`.

### `config/deploy.production.yml`

- **Committed:** yes
- **Format:** YAML
- **Purpose:** Production destination config.
- **Contains:** production hosts, roles, proxy host, PostgreSQL accessory, clear production env vars.
- **Used when:** running Kamal with `-d production`.

### `.kamal/secrets`

- **Committed:** yes
- **Format:** Kamal secrets file; shell-like comments/assignments
- **Purpose:** Default secrets file. Currently documents how destination secrets are organized.
- **Used when:** Kamal resolves secrets.

### `.kamal/secrets-common`

- **Committed:** yes
- **Format:** Kamal secrets file; shell-like assignment
- **Purpose:** Shared secret mappings for all destinations.
- **Contains:** `KAMAL_REGISTRY_PASSWORD=$GHCR_TOKEN`.
- **Depends on:** local `GHCR_TOKEN` environment variable.
- **Used when:** Kamal logs in to GHCR to push or pull images.

### `.kamal/secrets.staging`

- **Committed:** yes
- **Format:** Kamal secrets file; shell-like assignments with command substitution
- **Purpose:** Staging secret mappings.
- **Contains:** database password mapping and Rails master key loading.
- **Depends on:** `POSTGRES_PASSWORD_STAGING` and `config/credentials/staging.key`.
- **Used when:** running Kamal with `-d staging`.

### `.kamal/secrets.production`

- **Committed:** yes
- **Format:** Kamal secrets file; shell-like assignments with command substitution
- **Purpose:** Production secret mappings.
- **Contains:** database password mapping and Rails master key loading.
- **Depends on:** `POSTGRES_PASSWORD_PRODUCTION` and `config/credentials/production.key`.
- **Used when:** running Kamal with `-d production`.

### `config/credentials/staging.yml.enc`

- **Committed:** yes
- **Format:** Rails encrypted credentials
- **Purpose:** Encrypted staging Rails secrets.
- **Depends on:** `RAILS_MASTER_KEY`, loaded from `config/credentials/staging.key` during deploy.
- **Used when:** the staging app boots.

### `config/credentials/production.yml.enc`

- **Committed:** yes
- **Format:** Rails encrypted credentials
- **Purpose:** Encrypted production Rails secrets.
- **Depends on:** `RAILS_MASTER_KEY`, loaded from `config/credentials/production.key` during deploy.
- **Used when:** the production app boots.

### `config/credentials/staging.key`

- **Committed:** no, gitignored
- **Format:** plain text secret key
- **Purpose:** Decrypts `config/credentials/staging.yml.enc`.
- **Used by:** `.kamal/secrets.staging`.

### `config/credentials/production.key`

- **Committed:** no, gitignored
- **Format:** plain text secret key
- **Purpose:** Decrypts `config/credentials/production.yml.enc`.
- **Used by:** `.kamal/secrets.production`.

## Local environment variables

Required on a developer machine that deploys:

```bash
GHCR_TOKEN
POSTGRES_PASSWORD_STAGING
POSTGRES_PASSWORD_PRODUCTION
```

## New machine checklist

```bash
# Add local credential keys
cp staging.key config/credentials/staging.key
cp production.key config/credentials/production.key

# Export deploy secrets
export GHCR_TOKEN=...
export POSTGRES_PASSWORD_STAGING=...
export POSTGRES_PASSWORD_PRODUCTION=...

# Verify merged Kamal config
bin/kamal config -d staging
bin/kamal config -d production

# Deploy
bin/kamal deploy -d staging
bin/kamal deploy -d production
```
