# Email Emulation in Development

In development and test environments, the app does not send real emails. Outgoing mail is captured to disk and viewable through a built-in inbox UI.

## How it works

- `config.action_mailer.delivery_method = :file` (see `config/environments/development.rb`) routes outgoing mail through `lib/file_delivery.rb`.
- `config.email_storage_adapter = :file_system` persists captured messages via `EmailStorage::FileSystemStorage`.
- Routes under `namespace :development` are mounted only when `Rails.env.development? || Rails.env.test?`.

## Viewing captured emails

- `GET /development/sent_emails` — list all captured messages.
- `GET /development/sent_emails/:id` — view a single message.
- `DELETE /development/sent_emails/purge` — clear the inbox.
