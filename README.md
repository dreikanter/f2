# Feeder

[![codecov](https://codecov.io/gh/dreikanter/f2/graph/badge.svg?token=8OTZNI2092)](https://codecov.io/gh/dreikanter/f2)

Web application for scheduling and publishing content feeds to FreeFeed.

## Stack

- Rails (edge), PostgreSQL
- SolidQueue for background jobs
- Turbo, Stimulus, Tailwind CSS + DaisyUI
- Kamal deployment

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

## Testing

```bash
bin/rails test
```
