# Upgrading PostgreSQL

PostgreSQL major versions (e.g. 18 → 19) are not on-disk compatible: a server built for the new version will refuse to start against a data directory written by the old one. Minor versions (e.g. 18.1 → 18.2) are compatible and are picked up by simply pulling a fresh image.

The version is set in three places that must move together:

- `config/deploy.yml` — the `db` accessory image (`postgres:<major>`)
- `.github/workflows/ci.yml` — the test service image
- `docs/manual-testing.md` — local `pg_ctl` paths (only if you use that flow)

The rest of this guide covers how to roll a major upgrade across each environment.

## Development

Dev data is disposable, so the simplest path is to wipe and rebuild.

If running PostgreSQL through Homebrew, system packages, or `pg_ctl` directly:

1. Stop the running cluster.
2. Install the new major version alongside or in place of the old one.
3. Drop the old data directory (or initialise a fresh one for the new version).
4. Start the new server and run `bin/rails db:prepare db:seed`.

If running PostgreSQL via Docker locally, stop the container, remove its volume, and start a new container on the bumped tag.

After the server is up, bump `postgres:<major>` in `config/deploy.yml` and `.github/workflows/ci.yml` and commit the change. Keep these in lockstep with whatever you're running locally so CI and prod don't drift.

## Staging (disposable data)

Staging is allowed to lose its database. The flow mirrors the "clean slate" section of `docs/deploy-staging.md`.

1. Edit `config/deploy.staging.yml` (or `config/deploy.yml` if staging shares it) and bump the `db` accessory image:

   ```yaml
   accessories:
     db:
       image: postgres:<new-major>
   ```

2. Commit and push the change.

3. Stop the accessory and remove its data volume:

   ```bash
   bin/kamal accessory stop db -d staging
   bin/kamal accessory remove db -d staging   # prompts; deletes the data volume
   ```

4. Boot the accessory at the new version and recreate the schema:

   ```bash
   bin/kamal accessory boot db -d staging
   bin/kamal app exec --reuse "bin/rails db:prepare" -d staging
   bin/kamal app exec --reuse "bin/rails db:seed" -d staging
   ```

5. Bump CI (`.github/workflows/ci.yml`) to the same major in the same commit as step 1, so test runs match.

If the upgrade misbehaves, you can roll back by reverting the tag and rebooting the accessory — there is no data to preserve.

## Production (data migration required)

Production data must survive the upgrade. Kamal's accessory model only runs one image at a time, so the practical path is **dump from the old version, boot the new version on an empty volume, restore**. Plan for downtime equal to the dump + restore time.

### 1. Pre-flight

- Announce a maintenance window. The app will be unavailable while the database is offline.
- Read the [PostgreSQL release notes](https://www.postgresql.org/docs/release/) for the target major version, especially the "Migration to Version X" section.
- Make sure the workstation running these commands has enough free disk for the dump file.

### 2. Take a backup

From the workstation:

```bash
bin/kamal accessory exec db --reuse \
  "pg_dump -U f2 -Fc -d f2_staging" -d production > f2-prod-$(date +%F).dump
```

`-Fc` produces a custom-format archive that `pg_restore` can stream into the new server. Verify the file is non-empty and copy it somewhere durable before continuing.

### 3. Stop the app

```bash
bin/kamal app stop -d production
```

This prevents writes during the migration. Background jobs stop with the app container.

### 4. Bump the accessory image

Edit `config/deploy.yml`:

```yaml
accessories:
  db:
    image: postgres:<new-major>
```

Commit the change.

### 5. Replace the data volume

The existing volume holds a cluster from the old major and will not boot under the new version. Stop the accessory and remove the volume:

```bash
bin/kamal accessory stop db -d production
bin/kamal accessory remove db -d production   # prompts; deletes the data volume
```

This is the destructive step. Do not proceed past it without a verified dump from step 2.

### 6. Boot the new version

```bash
bin/kamal accessory boot db -d production
```

The container initialises an empty cluster on the new major version.

### 7. Restore

Stream the dump back in:

```bash
cat f2-prod-<date>.dump | \
  bin/kamal accessory exec db --reuse \
  "pg_restore -U f2 -d f2_staging --clean --if-exists --no-owner" -d production
```

Adjust the database name (`f2_staging` vs `f2_production`) to match what's actually configured for the destination.

### 8. Bring the app back up

```bash
bin/kamal app boot -d production
bin/kamal app exec --reuse "bin/rails db:migrate" -d production
curl -I https://<prod-host>/up
```

Smoke-test the critical paths (sign in, list feeds, create a feed) before declaring the window closed.

### 9. Update CI

In a follow-up commit (or the same release branch), bump `.github/workflows/ci.yml` to match. Production and CI must run the same major after the dust settles.

### Rollback

If the new server fails to start or the restore errors out:

1. Revert the image tag in `config/deploy.yml` to the previous major.
2. Remove the (likely partial) new data volume: `bin/kamal accessory remove db -d production`.
3. `bin/kamal accessory boot db -d production` to get the old version back.
4. Restore the dump from step 2 — it was taken from the old version and is compatible with itself.
5. `bin/kamal app boot -d production`.

Investigate the failure offline before retrying the upgrade.
