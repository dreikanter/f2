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
