# F2 Project Memory

## Tech Stack
- Rails 8.0.2 with PostgreSQL
- Authentication: bcrypt, sessions, password reset
- Frontend: Turbo, Stimulus, Bootstrap CSS
- Deployment: Kamal

## Current State
- Basic authentication system complete
- User/Session models with secure passwords
- Dashboard as root route
- Branch: feature/feeds-configuration
- Modified: Gemfile, Gemfile.lock

## Key Files
- `app/models/user.rb` - User model with authentication
- `app/controllers/concerns/authentication.rb` - Auth logic
- `config/routes.rb` - Simple routing setup