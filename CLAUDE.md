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

## Specs

Specs in `specs/` are historical records committed **together with their implementation**. A spec directory appears in the repo only when the described work has shipped. They are ordered chronologically (`001-`, `002-`, …). If the codebase diverges from a spec's text, a later spec or PR evolved the design — the code is the source of truth, the spec is the rationale record.

## Error Reporting

Report handled exceptions through `Rails.error`.

```ruby
Rails.error.report(e, context: { feed_id: feed.id })

Rails.error.handle(SomeExpectedError, context: { ... }) do
  do_work
end
```

## PR description

Use `.github/pull_request_template.md` for PR descriptions.

Keep the description focused on purpose and conceptual level — what the
change accomplishes and why. Don't enumerate every technical detail in
the diff; reviewers can read the diff. A few bullets or a short paragraph
is usually enough.

Structure:
- `Changes:` bullet list at the top describing what was done
- Optional prose paragraph explaining the rationale
- `References:` section at the bottom listing related issues/PRs (e.g. `Closes #123`); omit entirely if there are none
- Do **not** include session links or any `https://claude.ai/...` URLs

After creating a PR, check the body for any harness-injected session URLs (e.g. `https://claude.ai/code/session_...`) and remove them by updating the PR.

## Tooling Notes

- Use mise for managing Ruby and Node runtimes (local dev).
- **Remote Claude Code environments** don't have mise. The session-start hook (`.claude/hooks/session-start.sh`) sets up Ruby via rbenv, starts PostgreSQL, and installs gems automatically. Run binstubs directly after that.
- Run Rails binstubs directly: `bin/rails test`, `bin/rubocop -f github`.

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

<!-- SPECKIT START -->
Active feature: **smart-feed-creation** (delivered across multiple PRs).
For technical context, project structure, and conventions for this feature,
read [`specs/001-smart-feed-creation/plan.md`](specs/001-smart-feed-creation/plan.md).
<!-- SPECKIT END -->
