# F2 Project Memory

## Tech Stack
- Rails 8.0.2 with PostgreSQL
- Authentication: bcrypt, sessions, password reset
- Frontend: Turbo, Stimulus, Bootstrap CSS
- Deployment: Kamal
- Background Jobs: SolidQueue with recurring scheduler

## Current State
- Feed models with cron-based scheduling
- ActiveJob scheduler running every minute
- Comprehensive test coverage with FactoryBot
- SimpleCov + Codecov integration
- Branch: feature/scheduler

## Key Files
- `app/models/feed.rb` - Feed model with scheduling scope
- `app/jobs/feed_scheduler_job.rb` - Recurring job to queue due feeds
- `app/jobs/feed_refresh_job.rb` - Individual feed processing
- `config/recurring.yml` - SolidQueue recurring job configuration

## Version Control
- *Always* use atomic commits unless asked differently
- Write concise one-line commit messages in imperative mood (e.g., "Add user authentication" not "Added user authentication")
- Separate logically distinct changes in the same file into separate commits when it makes sense
- Never add reference to yourself in commit messages

## Devlopment Practices
- Run RuboCop after you change code
- Rubocop command is the command is `bin/rubocop`
- Correct the code if RuboCop return errors
