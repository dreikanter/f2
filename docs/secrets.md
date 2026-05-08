# Secrets Management

## Convention

- Encrypted credentials are used **only in staging and production**.
- In **development and test**, `Rails.application.credentials` is empty by design. Every read returns `nil`. There is no `config/master.key` and no base `config/credentials.yml.enc`.
- Code that reads credentials must be nil-safe so the dev server and the test suite boot without a key.
- Non-secret per-environment configuration goes in `.env` (gitignored). See `.env.sample` for the template. Do not put secrets in `.env`.

## Layout

| Path | Purpose | Tracked? |
| --- | --- | --- |
| `config/credentials/staging.yml.enc` | Staging secrets, encrypted with `staging.key`. | yes |
| `config/credentials/staging.key` | Decryption key for staging. | gitignored |
| `config/credentials/production.yml.enc` | Production secrets, encrypted with `production.key`. | yes |
| `config/credentials/production.key` | Decryption key for production. | gitignored |

`RAILS_MASTER_KEY` is the env var Rails reads when no `.key` file is present. Kamal sets it from `.kamal/secrets.staging` or `.kamal/secrets.production`, which read the matching `config/credentials/<env>.key` file.

## Reading credentials in code

```ruby
Rails.application.credentials.dig(:resend_api_token)
Rails.application.credentials.dig(:honeybadger, :api_key)
```

In dev and test these return `nil`. Every call site must tolerate that:

- **Optional integrations** — pass the value through to the gem and let it self-disable. Honeybadger does this when `api_key` is `nil`. The Resend mailer is never invoked in dev because `config.action_mailer.delivery_method = :file` (development) and `:test` (test).
- **Required values** — guard explicitly, e.g. `return head :unauthorized if secret.blank?` (see `app/controllers/resend_webhooks_controller.rb`).
- **Tests** — stub the credential per-test:

  ```ruby
  Rails.application.credentials.stub(:resend_signing_secret, "test_secret") do
    # ...
  end
  ```

When adding a new credential read, run `bin/rails server` and `bin/rails test` with no key present and confirm both still boot.

## Creating the credentials file for an environment

Run once per environment to generate the encrypted file and its key:

```bash
EDITOR="code --wait" bin/rails credentials:edit --environment staging
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

`--wait` is required for editors that detach by default (VS Code, Zed, Cursor). `vim`/`nano` work without it.

Each command produces:

- `config/credentials/<env>.yml.enc` — commit it.
- `config/credentials/<env>.key` — gitignored. Share via the team password manager.

Verify the key is ignored before doing anything else:

```bash
git check-ignore -v config/credentials/staging.key
```

Make the key available wherever the app boots in that environment:

- **Kamal:** `.kamal/secrets.staging` and `.kamal/secrets.production` export `RAILS_MASTER_KEY` from the matching `config/credentials/<env>.key` file.
- **CI:** export `RAILS_MASTER_KEY=<env-key>` as a CI secret if a job runs in staging or production mode.

## Use case: add a new secret

1. Open the file for the target environment:

   ```bash
   EDITOR="code --wait" bin/rails credentials:edit --environment staging
   EDITOR="code --wait" bin/rails credentials:edit --environment production
   ```

   Always pass `--environment`. There is no base `credentials.yml.enc` in this project, and creating one would silently override per-env files in dev/test.

2. Add the key. Use nesting for grouped values:

   ```yaml
   resend_api_token: re_xxxxxxxxxxxxxxxx
   honeybadger:
     api_key: hbp_xxxxxxxxxxxxxxxx
   ```

3. Save and close. Confirm only the encrypted file changed:

   ```bash
   git status config/credentials
   ```

4. Read the value in code with a nil-safe call:

   ```ruby
   Rails.application.credentials.dig(:resend_api_token)
   ```

5. Commit the encrypted file:

   ```bash
   git add config/credentials/production.yml.enc
   git commit -m "Add Resend API token to production credentials"
   ```

If the same secret is needed in staging, repeat step 1 with `--environment staging` and commit that file too.

## Use case: change an existing secret

Same flow — `bin/rails credentials:edit --environment <env>` decrypts in place. Update the value, save, commit the re-encrypted file.

If the secret is rotating because it leaked:

1. Revoke the old value at the provider first.
2. Edit the credentials file and replace the value.
3. Commit and deploy in the same change so callers pick up the new value immediately.
4. If the leak exposed an `<env>.key` file, rotate the key itself (see below) — replacing the secrets inside is not enough.

## Rotating a key

If a `.key` file is exposed:

1. Print the current contents: `bin/rails credentials:show --environment <env>`. Copy the YAML to the clipboard.
2. Delete the old pair: `git rm config/credentials/<env>.yml.enc && rm config/credentials/<env>.key`.
3. Create a fresh pair: `EDITOR="code --wait" bin/rails credentials:edit --environment <env>`. Paste the YAML, save.
4. Distribute the new `.key` via the password manager and update `RAILS_MASTER_KEY` wherever it is set (Kamal hosts, CI).
5. Commit and deploy.

## Troubleshooting

- **`ActiveSupport::EncryptedConfiguration::MissingKeyError`** — an encrypted file exists but no key is available. In dev/test this usually means a stale `config/credentials.yml.enc` was left behind; remove it. In staging/production, confirm `RAILS_MASTER_KEY` matches the `<env>.yml.enc` being decrypted.
- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — the key doesn't match the `.enc` file. Confirm the right `.key` is in place, or that `RAILS_MASTER_KEY` matches the environment.
- **`bin/rails credentials:edit` opens an empty file and exits immediately** — `$EDITOR` is detaching. Use a foreground command (`export EDITOR="code --wait"` or `export EDITOR=vim`).
- **A credential reads as `nil` in staging or production** — `Rails.env` doesn't match the file you edited, or the deploy didn't pick up `RAILS_MASTER_KEY`. `bin/rails credentials:show --environment <env>` prints the decrypted contents for the given env.
