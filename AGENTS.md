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

### Core Principle
Break work into logical, atomic units rather than massive changesets.
Never reference yourself in commit messages.
Use concise one-line imperative commit messages.
Generalize when explaining what was done.
Do NOT use the word comprehensive in commit messages and PR description.
If you need to use the word comprehensive in commit messages or PR description, **do not use it.**

### Best Practices

**Atomic Commits**: Each commit should represent one logical change (single feature, bug fix, or refactor). If you can't describe the commit in one clear sentence, it's probably too large.

**Frequent Commits**: Commit after completing each meaningful unit of work:
- Individual function implementations
- Single test additions
- Configuration updates
- Documentation sections
- Separate logically distinct changes in the same file into separate commits when it makes sense.

**Clear Messages**: Use descriptive commit messages that explain the "what" and "why":
```
Add user authentication middleware
Handle edge case in data validation
Update API endpoint documentation
```
Be concise.
Use imperative mood.

**Feature Branching**: For larger features, create branches and make incremental commits, then merge via pull request.

### Anti-Patterns to Avoid
- Committing all changes at end of session
- Mixing unrelated changes in single commit
- Vague messages like "updates" or "fixes"
- Committing broken/incomplete code

## Code style

Routing:

- Use resourceful routes.
- Prefer not to use `member` or `collection` routes.
- Prefer not to use individual routes for each action.

Controllers:

- Eliminate blank action methods.

Testing:

- Use factory_bot for test data.
