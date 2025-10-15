# F2 Project Memory

This repository contains the **Feeder** Rails 8 application for scheduling and refreshing feeds.

## Tech Stack

- Rails (edge) + PostgreSQL.
- Authentication via bcrypt sessions with password reset.
- Background jobs via SolidQueue using Fugit cron expressions.
- Frontend: Turbo, Stimulus, Bootstrap CSS
- Deployment: Kamal

## Commit Requirements

**Goal:** Every commit is a single, meaningful, self-contained change (e.g., DB migration, controller change, HTML layout tweak, test coverage improvement). No grab-bag commits. Keep the test suite green for each commit.

### Commit-before-you-code loop

1. **Plan → Split work:** Break the task into 3–7 smallest meaningful steps, each summarized in one short sentence (“Add X”, “Refactor Y”, “Fix Z”). If the message needs “and”, split it.
2. **Implement one step only.**
3. **Stage precisely:** use `git add -p` (or IDE line/selection staging) to include only the hunks that satisfy the one-sentence change.
4. **Run tests/linters:** keep the suite green per commit.
5. **Commit message (subject ≤ 50 chars, imperative):**

   * Subject: “Add user\_email index”
   * Body (optional): why + constraints/links.
6. **Repeat** for the next planned step. If changes get mixed, use `git reset -p`, `git commit --amend`, or `git rebase -i` to reorganize before pushing.

### What counts as “atomic”

* **Single purpose & complete:** one logical change, fully done.
* **Examples:**

  * “Add migration for `orders.status` enum” (+ entity change if required).
  * “Refactor `UserService` to use async/await” (no styling changes).
  * “Fix divide-by-zero in `calc()` + test.”

### Review yourself before push

* Inspect `git status`, `git diff`, `git log --oneline`.
* Squash/fixup only when several commits are fragments of the *same* unit of work.

### Guardrails

* **Never** stage unrelated edits together (formatting, renames, feature code in one commit).
* If mid-flow you discover a second concern, **stop** and create a new TODO line; do not keep coding in the same commit.
* Prefer many small PRs built from atomic commits; they’re easier to review, revert, and bisect.

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

- Ruby version is defined in `.ruby-version`.
- Follow standard Rails conventions.
- Use two-space indentation.

## PR description

Use the following format:

```
Changes:

- Change 1
- Change 2
- ...
```

When listing the changes, start from the most important. Generalize. Skip boring details.

## Testing

- Keep tests and code together.
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
