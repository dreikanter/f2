# Claude Code Configuration for F2

This directory contains Claude Code environment configuration for the F2 Rails project.

## Files

- **settings.json** - Shared environment configuration (committed to git)
- **settings.local.json** - Personal overrides (git-ignored, create if needed)
- **commands/** - Slash commands for common tasks
- **agents/** - Custom subagent definitions (add as needed)

## Environment Variables

The `settings.json` file configures:

- `RAILS_ENV=test` - Run in test environment
- `DATABASE_URL` - PostgreSQL connection for tests
- `RAILS_MAX_THREADS` - Thread pool size

## Available Slash Commands

- `/test` - Run the Rails test suite
- `/rubocop` - Run RuboCop and fix violations
- `/db-reset` - Reset the test database
- `/check` - Run full quality checks (tests + rubocop)

## Personal Overrides

Create `.claude/settings.local.json` for personal environment overrides:

```json
{
  "environment": {
    "DATABASE_URL": "postgresql://localhost/f2_test?pool=10"
  }
}
```

This file is git-ignored and won't affect other developers.
