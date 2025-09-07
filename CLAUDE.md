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

## Commit Message Guidelines
- Use ONLY the first line as commit message (max 72 chars)
- NO bullet points, explanations, or descriptions
- NO tool attribution or co-author tags
- Commits should be atomic - one small change per commit
- Examples:
  - Good: "Add user authentication middleware"
  - Bad: "Add user authentication middleware\n\n- Implements JWT validation\n- Adds error handling\n🤖 Generated with Claude Code"
  
## Development Practices
- Check and fix RuboCop violations after each change to the code (use command: `bin/rubocop`)
- Use FactoryBot to create test data
- Prefer lazy test data initialization over eager initialization in setup block

```ruby
# Bad:
setup do
  @user = create(:user)
  @feed = create(:feed, user: @user)
end

# Good:
def user
  @user ||= create(:user)
end

def feed
  @feed ||= create(:feed, user: user)
end
```
