# Email Emulation in Development

In development and test environments, the app does not send real emails. Outgoing mail is captured to disk and viewable through a built-in inbox UI.

## How it works

- `config.action_mailer.delivery_method = :file` (see `config/environments/development.rb`) routes outgoing mail through `lib/file_delivery.rb`.
- `config.email_storage_adapter = :file_system` persists captured messages via `EmailStorage::FileSystemStorage`.
- Routes under `namespace :development` are mounted only when `Rails.env.development? || Rails.env.test?`.

## Sender address

`MAILER_FROM` sets the sender for all outgoing mail. Development falls back to
`noreply@localhost` because nothing leaves the machine. Production and staging
have no fallback and refuse to boot without it: the address has to be on a
domain verified in the Resend workspace, and a wrong one is only rejected at
send time, long after the deploy looked healthy. The effective value is shown
under Configuration on `/development/system_status`.

## Viewing captured emails

With the Rails server running, open `/development/sent_emails` in your browser to see the inbox of captured messages. Click any entry to read it. Use the "Purge All" button to clear the inbox when you want a clean slate.
