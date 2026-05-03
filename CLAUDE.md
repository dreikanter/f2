# F2 Project Memory

This repository contains the **Feeder** application for reposting content from external sources to Freefeed social network.

## Tech Stack

- Rails (edge) + PostgreSQL.
- Background jobs via SolidQueue.
- Frontend: Turbo, Stimulus
- Deployment: Kamal

## Commit Requirements

Practice atomic commits: each commit should be one meaningful, complete change.

- Split work into small steps before coding.
- Implement one step at a time.
- Stage only related hunks, preferably with `git add -p`.
- Run the relevant tests/linters before each commit.
- Use short imperative subjects, 50 characters or less.
- Keep unrelated cleanup, formatting, and feature work in separate commits.
- Review `git status`, `git diff`, and `git log --oneline` before pushing.

## Code style

File formatting:

- Always add trailing line breaks to source files (Ruby, JS, CSS, HTML, etc.) unless there is a specific reason not to.
- This ensures consistent formatting and prevents RuboCop/linter warnings.

Routing:

- Use resourceful routes.
- Prefer not to use `member` or `collection` routes.
- Prefer not to use individual routes for each action.

Controllers:

- Eliminate blank action methods.

## UI Text Writing

When writing user-facing text in views, keep it approachable and practical:

- **Tone:** Friendly but not overly familiar. Avoid stiff, formal language but also avoid being too casual or cutesy.
- **Clarity:** Be brief and easily digestible. Don't overwhelm users with terminology or long explanations.
- **Voice:** Write like you're explaining something to a person, not documenting it in a reference manual.
- **Goal:** Make the interface feel chill and non-boring, but still respectful and clear.

Examples:

```erb
<!-- Bad: Too formal -->
<p>You have successfully completed the onboarding process and may repeat it at any time.</p>

<!-- Bad: Too technical -->
<p>The onboarding wizard has been finalized. Re-initialization is available via the button below.</p>

<!-- Good: Approachable and clear -->
<p>Want a quick refresher? Run through the setup steps again to get familiar with how everything works.</p>
```

```erb
<!-- Bad: Too casual -->
<p>Hey there! Wanna do that onboarding thing again? Hit this button!</p>

<!-- Good: Friendly but professional -->
<p>Need to walk through the setup again? No problem.</p>
```

When writing instructions or explanations:
- Focus on what the user needs to do and why it matters to them
- Break complex concepts into simple, digestible pieces
- Use active voice and direct language
- Avoid unnecessary jargon unless it's standard terminology users should learn
- **Don't expose UI implementation details:** Avoid terms like "wizard", "form", "dialog", "modal", "interface", "screen", etc. Instead, focus on what the user is doing or what's happening.

## Development Guidelines

- Follow standard Rails conventions.

## PR description

Use `.github/pull_request_template.md` for PR descriptions.

## Tooling Notes

- Use mise for managng Ruby and Node runtimes.
- Use `mise exec --` to run Ruby/Bundler commands.
- Assume Ruby environment already has required gems installed, so avoid installing or updating gems during tasks.

## Testing

- Keep tests and code changes together.
- Add or update tests for any code change.
- Verify database migrations work both ways (up/down).
- Run test before committing: `bin/rails test`.
- Use FactoryBot to create test data.
- Check and fix RuboCop violations after each change to the code (use command: `bin/rubocop -f github`).
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

### Test naming convention

Use the format `test "#method should ..."` for unit tests:

```ruby
# Bad:
test "time_ago returns nil for nil input" do
  # ...
end

# Good:
test "#time_ago should return nil for nil input" do
  # ...
end
```

### Testing hooks (data attributes)

- Prefer `data-key` attributes for DOM selectors in tests; they clarify intent and avoid coupling to styling classes.
- Example in a component: `tag.li class: "…", data: { key: "stats.total_feeds" }`.
- In tests, query via `css_select('[data-key="stats.total_feeds"]')`.
- Keep keys short, namespaced (`component.element`) for readability.
