# AGENTS Instructions

This repository contains the **Feeder** Rails 8 application for scheduling and refreshing feeds.

## Project Overview

- Rails (edge) + PostgreSQL.
- Authentication via bcrypt sessions with password reset.
- Background jobs via SolidQueue using Fugit cron expressions.

## Development Guidelines

- Ruby version is defined in `.ruby-version`.
- Follow standard Rails conventions.
- Use two-space indentation.
- Keep tests and code together.
- Add or update tests for any code change.

## Testing

- Verify database migrations work both ways (up/down).
- Run these commands before committing:
  - `bin/rubocop` – ensures Ruby style follows the Omakase RuboCop rules.
  - `bin/rails test` – runs the full test suite.

## Version control

- *Always* use atomic commits unless asked differently.
- Write concise one-line commit messages in imperative mood (e.g., "Add user authentication" not "Added user authentication").
- Do not explain every single change in the commit message, generalize.
- Separate logically distinct changes in the same file into separate commits when it makes sense.
- Never add reference to yourself in commit messages.

## Code style

Routing:

- Use resourceful routes.
- Prefer not to use `member` or `collection` routes.
- Prefer not to use individual routes for each action.

Controllers:

- Eliminate blank action methods.

Testing:

- Use factory_bot for test data.
