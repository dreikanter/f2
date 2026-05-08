# Secrets Management

Feeder keeps secret values (API tokens, signing secrets, third-party keys) in Rails encrypted credentials. The decryption key lives outside the repo: locally in `config/credentials/<env>.key`, and in production as the `RAILS_MASTER_KEY` environment variable injected by Kamal.

Non-secret per-environment configuration goes in `.env` (gitignored) and is documented in `.env.sample`. Do not put secrets in `.env`.

## How it fits together

- `config/credentials.yml.enc` — shared/base credentials, decrypted with `config/master.key`. Used when no environment-specific file exists.
- `config/credentials/<env>.yml.enc` — encrypted credentials for a single environment (e.g. `staging`, `production`), decrypted with `config/credentials/<env>.key`.
- `config/credentials/<env>.key` and `config/master.key` — gitignored. Treat as sensitive; share via a password manager.
- `RAILS_MASTER_KEY` — environment variable Rails reads when the matching `.key` file is absent. Kamal sets it from `.kamal/secrets` (which reads `config/credentials/<env>.key` on the deploy host or pulls from a password manager).

Rails picks the file matching `Rails.env`, falling back to the base `credentials.yml.enc`. Code reads values via `Rails.application.credentials`:

```ruby
Rails.application.credentials.dig(:resend_api_token)
Rails.application.credentials.dig(:honeybadger, :api_key)
```

## Creating an environment-specific credentials file

Use this when a new environment needs its own secrets (e.g. bringing up `staging`). It generates the encrypted file and the matching key.

```bash
EDITOR="code --wait" bin/rails credentials:edit --environment staging
```

This creates:

- `config/credentials/staging.yml.enc` (commit it)
- `config/credentials/staging.key` (gitignored; share via password manager)

Verify the key is gitignored before doing anything else:

```bash
git check-ignore -v config/credentials/staging.key
```

Then store the key in the team password manager and make it available wherever the app boots:

- **Local:** keep the `.key` file in place; Rails will read it automatically.
- **Kamal/production:** export `RAILS_MASTER_KEY` before deploy, or reference it from `.kamal/secrets` (see `.kamal/secrets` for the pattern already used for the default key).

## Use case: add a new secret

1. Open the file for the target environment:

   ```bash
   EDITOR="code --wait" bin/rails credentials:edit                          # base
   EDITOR="code --wait" bin/rails credentials:edit --environment staging    # staging
   EDITOR="code --wait" bin/rails credentials:edit --environment production # production
   ```

   Rails decrypts the file into a temp file, opens it in `$EDITOR`, then re-encrypts and writes it back when the editor exits. `--wait` is required for editors that detach by default (VS Code, Zed, Cursor); `vim`/`nano` work without it.

2. Add the key. Use nesting for grouped values:

   ```yaml
   resend_api_token: re_xxxxxxxxxxxxxxxx
   honeybadger:
     api_key: hbp_xxxxxxxxxxxxxxxx
   ```

3. Save and close. Confirm the encrypted file changed and the key file did not:

   ```bash
   git status config/credentials*
   ```

4. Read the value in code:

   ```ruby
   Rails.application.credentials.dig(:resend_api_token)
   ```

5. Commit the encrypted file:

   ```bash
   git add config/credentials.yml.enc        # or config/credentials/staging.yml.enc
   git commit -m "Add Resend API token"
   ```

## Use case: change an existing secret

Same flow as adding — `bin/rails credentials:edit` decrypts in place. Update the value, save, and commit the re-encrypted file.

If the secret is rotating because it leaked:

1. Revoke the old value at the provider first.
2. Edit credentials and replace the value.
3. Commit and deploy in the same change so callers pick up the new value immediately.
4. If the leak exposed `master.key` or any `<env>.key`, rotate the master key itself (see below) — rotating only the secrets inside is not enough.

## Rotating a master key

If a `.key` file is exposed, the encrypted file must be re-encrypted under a new key:

1. Decrypt and copy the current contents (`bin/rails credentials:edit` and copy the YAML).
2. Delete the old `.enc` and `.key` pair.
3. Run `bin/rails credentials:edit --environment <env>` to generate a fresh pair.
4. Paste the contents back, save.
5. Distribute the new `.key` via password manager and update `RAILS_MASTER_KEY` wherever it is set (Kamal hosts, CI).
6. Deploy.

## Troubleshooting

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — the key doesn't match the `.enc` file. Confirm the right `.key` is present, or that `RAILS_MASTER_KEY` matches the environment's `.enc` file.
- **`bin/rails credentials:edit` opens an empty file and exits immediately** — `$EDITOR` is detaching. Set it to a foreground command (`export EDITOR="code --wait"` or `export EDITOR=vim`).
- **Secret reads as `nil` in code** — `Rails.env` doesn't match the file you edited. `bin/rails credentials:show --environment <env>` prints the decrypted contents for the given env.
