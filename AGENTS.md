# AGENTS Instructions

This repository contains the **Feeder** Rails 8 application for scheduling and refreshing feeds.

## Project Overview
- Rails 8 + PostgreSQL
- Authentication via bcrypt sessions with password reset
- Background jobs via SolidQueue using Fugit cron expressions
- Key files: `app/models/feed.rb`, `app/jobs/feed_scheduler_job.rb`, `app/jobs/feed_refresh_job.rb`, `config/recurring.yml`

## Development Guidelines
- Use Ruby `3.3.5` (see `.ruby-version`).
- Follow standard Rails conventions and use two-space indentation.
- Keep tests and code together; add or update tests for any code change.

## Required Checks
Run these commands before committing:

- `bin/rubocop` – ensures Ruby style follows the Omakase RuboCop rules.
- `bin/rails test` – runs the full test suite.

