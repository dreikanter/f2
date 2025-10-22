# Feeder

[![codecov](https://codecov.io/gh/dreikanter/f2/graph/badge.svg?token=YOUR_TOKEN)](https://codecov.io/gh/dreikanter/f2)

Rails 8 app for scheduling and publishing RSS/Atom feeds to FreeFeed.

## Stack

- Rails (edge), PostgreSQL
- SolidQueue for background jobs (Fugit cron)
- Turbo, Stimulus, Bootstrap
- Bcrypt sessions, Kamal deployment

## Development

```bash
bin/setup
bin/rails server
bin/rails test
bin/rubocop -f github
```

Ruby version: see `.ruby-version`

## Architecture

- **Feed refresh workflow**: Load → Process → Filter → Persist → Normalize → Publish
- **Normalizers**: Transform feed entries to FreeFeed posts (RSS, XKCD)
- **Validation**: Reject posts with missing content/URLs, track metrics
- **Sparse metrics**: Only record daily stats when there's activity

## Commit Style

Atomic commits, one logical change each. Subject ≤50 chars, imperative mood. Run tests + RuboCop before committing. Use `git add -p` for precise staging.

## Testing

Minitest + FactoryBot. Lazy test data initialization preferred. Keep tests green per commit.

See [CLAUDE.md](CLAUDE.md) for detailed guidelines.
