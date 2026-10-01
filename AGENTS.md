# F2 agent instructions

Feeder reposts content from external sources to the FreeFeed social network.

## Verification

- **VERIFY-01:** Before finishing, review each applicable requirement against the
  actual changes. Report unmet requirements and verification limitations, with
  commands or evidence. A full compliance report is unnecessary.
- **VERIFY-02:** Keep requirement IDs globally unique across the repository's
  `AGENTS.md` files, with a distinct prefix for each section. Preserve existing
  IDs; do not renumber or reuse them when requirements are added or removed.

## Testing

- **TEST-01:** Cover new or changed behavior with meaningful tests in the same
  commit. Existing tests may suffice for behavior-preserving refactors;
  do not change tests solely to accompany a code edit.
- **TEST-02:** Before committing, run the tests and linters relevant to the
  changes: `bin/rails test [paths]`, `yarn test:javascript`, and
  `bin/rubocop -f github`. State which checks ran and any failures or skips.
- **TEST-03:** Verify new or changed database migrations both up and down.
- **TEST-04:** Use FactoryBot for test data. Prefer lazy helpers over eager shared setup.
- **TEST-05:** Name unit tests `test "#method should ..."`.
- **TEST-06:** Use short, namespaced `data-key` selectors in DOM tests, such as
  `data-key="stats.total_feeds"`, rather than styling classes.

## Git and pull requests

- **GIT-01:** Keep each commit focused on one meaningful, complete change.
  Separate unrelated cleanup and use imperative subjects of 50 characters or less.
- **GIT-02:** For user-facing changes, add a short bullet to `CHANGELOG.md` in the
  same commit, under today's `## YYYY-MM-DD` heading (newest first, no blank lines
  between bullets). Omit internal refactors, test changes, dependency updates,
  and build/CI work unless users are affected.
- **GIT-03:** Use [.github/pull_request_template.md](.github/pull_request_template.md).
  Describe purpose and resulting behavior briefly; omit implementation inventories
  and session URLs. Check generated titles and descriptions and correct deviations.

## Code

- **CODE-01:** Prefer resourceful routes, extracting a resource instead of `member`,
  `collection`, or individual action routes. Omit empty controller actions.
- **CODE-02:** In multiline hashes, put each entry on its own line and braces on separate lines.
- **CODE-03:** Keep comments concise and focused on intent, trade-offs, or non-obvious
  constraints. Remove obsolete history and obvious narration; retain references
  or boundary explanations when they explain a lasting constraint or workaround.
- **CODE-04:** Preserve useful YARD `@param` and `@return` annotations without filler descriptions.
- **CODE-05:** Report handled exceptions through `Rails.error` with relevant
  context, using `Rails.error.report` or `Rails.error.handle`.

## User interface

- **UI-01:** Use semantic color tokens from the `@theme` block in
  `app/assets/stylesheets/application.css`, such as `text-body` and `bg-surface`.
  Add or edit tokens instead of introducing raw Tailwind palette shades.
- **UI-02:** Write UI text in brief, direct, friendly language. Avoid cutesy phrasing
  and implementation jargon; focus on the user's action and its purpose.

## Tooling

- **TOOL-01:** Use mise for Ruby and Node in local development; run Rails binstubs directly.
- **TOOL-02:** Remote Claude Code sessions use the dev container started by the session
  hook. Prefix Rails/RuboCop commands with `docker compose exec app`. See
  [docs/claude-remote-env.md](docs/claude-remote-env.md) for setup and troubleshooting.
- **TOOL-03:** Follow the JavaScript test prerequisites in [README.md](README.md#testing).
- **TOOL-04:** Treat `bin/critic` as advisory, not a gate. Read the known false positives
  in [docs/code-quality.md](docs/code-quality.md) before acting on its output.
- **TOOL-05:** For accurate coverage, run tests with `COVERAGE=1` to disable parallelism.
  See [docs/code-quality.md](docs/code-quality.md#test-coverage) for inspection commands.

## Design records

- **SPEC-01:** Treat specs in `specs/` as design and rationale records that may span
  multiple PRs. The code describes current behavior; specs can describe earlier
  or unfinished work.
