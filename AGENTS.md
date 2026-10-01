# F2 agent instructions

Feeder reposts content from external sources to the FreeFeed social network.

## Verification

Before finishing, review each rule below for applicability and verify it against
the actual changes. Report unmet requirements and verification limitations, with
the commands or evidence behind the result. A full compliance report is unnecessary.
Keep rule IDs stable; do not renumber or reuse them when rules are added or removed.

- **R01 - Tests:** Cover new or changed behavior with meaningful tests in the
  same commit. Existing tests may suffice for behavior-preserving refactors;
  do not change tests solely to accompany a code edit.
- **R02 - Checks:** Before committing, run the tests and linters relevant to the
  changes: `bin/rails test [paths]`, `yarn test:javascript`, and
  `bin/rubocop -f github`. State which checks ran and any failures or skips.
- **R03 - Migrations:** Verify new or changed database migrations both up and down.
- **R04 - Commits:** Keep each commit focused on one meaningful, complete change.
  Separate unrelated cleanup and use imperative subjects of 50 characters or less.
- **R05 - Changelog:** For user-facing changes, add a short bullet to
  `CHANGELOG.md` in the same commit, under today's `## YYYY-MM-DD` heading
  (newest first, no blank lines between bullets). Omit internal refactors,
  test changes, dependency updates, and build/CI work unless users are affected.
- **R06 - Pull requests:** Use [.github/pull_request_template.md](.github/pull_request_template.md).
  Describe purpose and resulting behavior briefly; omit implementation inventories
  and session URLs. Check generated titles and descriptions and correct deviations.
- **R07 - Colors:** Use semantic color tokens from the `@theme` block in
  `app/assets/stylesheets/application.css`, such as `text-body` and `bg-surface`.
  Add or edit tokens instead of introducing raw Tailwind palette shades.
- **R08 - Errors:** Report handled exceptions through `Rails.error` with relevant
  context, using `Rails.error.report` or `Rails.error.handle`.

## Code and writing

- Prefer resourceful routes, extracting a resource instead of `member`,
  `collection`, or individual action routes. Omit empty controller actions.
- In multiline hashes, put each entry on its own line and braces on separate lines.
- Keep comments concise and focused on intent, trade-offs, or non-obvious
  constraints. Remove obsolete history and obvious narration; retain references
  or boundary explanations when they explain a lasting constraint or workaround.
- Preserve useful YARD `@param` and `@return` annotations without filler descriptions.
- Write UI text in brief, direct, friendly language. Avoid cutesy phrasing and
  implementation jargon; focus on the user's action and its purpose.
- Use FactoryBot for test data. Prefer lazy helpers over eager shared setup.
- Name unit tests `test "#method should ..."`.
- Use short, namespaced `data-key` selectors in DOM tests, such as
  `data-key="stats.total_feeds"`, rather than styling classes.

## Tooling

- Local development uses mise for Ruby and Node; run Rails binstubs directly.
- Remote Claude Code sessions use the dev container started by the session hook.
  Prefix Rails/RuboCop commands with `docker compose exec app`. See
  [docs/claude-remote-env.md](docs/claude-remote-env.md) for setup and troubleshooting.
- JavaScript test prerequisites are in [README.md](README.md#testing).
- `bin/critic` is advisory, not a gate. Read the known false positives in
  [docs/code-quality.md](docs/code-quality.md) before acting on its output.
- For accurate coverage, run tests with `COVERAGE=1` to disable parallelism.
  See [docs/code-quality.md](docs/code-quality.md#test-coverage) for inspection commands.

## Design records

Specs in `specs/` record design and rationale and may span multiple PRs.
The code describes current behavior; specs can describe earlier or unfinished work.
