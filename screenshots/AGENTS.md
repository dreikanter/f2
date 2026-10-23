# Screenshots

Instructions for capturing and publishing actual app screenshots. Kept reference
screenshots document specific UI states so another agent can reproduce them.

## Capture and inspect

- **SHOT-CAPTURE-01:** Run the changed code in the development server. Verify HTTP
  readiness, sign in with an appropriate local account, and open the exact route.
  A process ID alone does not establish readiness. Do not reseed or change account
  permissions just to obtain a screenshot when an appropriate account exists.
- **SHOT-CAPTURE-02:** Use the available supported browser workflow. Wait for the
  intended page state, assets, and fonts before capture. Prefer a 1280px desktop
  viewport and capture the whole page or the relevant section, according to what
  demonstrates the change. Check a narrow viewport when layout behavior matters.
- **SHOT-CAPTURE-03:** Inspect the resulting image before publishing it. Confirm
  that the changed UI is visible, values come from the running app, text is legible,
  and the image contains no credentials or unintended private data. Do not replace
  an actual screenshot with generated artwork or a reconstructed mockup.
- **SHOT-CAPTURE-04:** Keep review captures in a task scratch directory outside
  the tracked tree (for example, `/workspace/work` in the cloud environment).
  Repository screenshots are opt-in reference artifacts. Apply the naming and
  annotation rules below when creating files in `screenshots/`, including during
  a temporary upload.

## Publish to GitHub

- **SHOT-PUBLISH-01:** Publish where the user asked: PR description, comment, or
  both. Read the current description before editing it and preserve its existing
  content. A description update requires no extra comment unless requested.
- **SHOT-PUBLISH-02:** Prefer GitHub's attachment uploader when it is available.
  The GitHub connector's comment and PR update tools accept Markdown but may lack
  an attachment-upload tool. That limitation does not prevent image embeds:
  `![Descriptive alt text](https://host/path/to/image.png)` works in both places.
  Never embed a local filesystem path or invent an attachment URL.
- **SHOT-PUBLISH-03:** Reuse an existing verified GitHub-hosted image URL when
  available. Otherwise, use the temporary upload workflow below if attachments
  are unavailable. A screenshot-sharing request authorizes this workflow, but an
  explicit prohibition on even temporary commits takes precedence. Never leave
  screenshot files or their commit in the final PR unless the user requests them.
- **SHOT-PUBLISH-04:** After cleanup, fetch the exact embedded URL with redirects
  and verify a successful image response and matching bytes. Read back the posted
  comment or description. When possible, also check GitHub's rendered HTML or the
  browser to confirm an image element appears at the requested destination.
- **SHOT-PUBLISH-05:** Return a link to the PR description or specific comment.
  Tool image output is not proof the user can see an image in chat. If the user
  reports it missing, provide a verified accessible destination instead of
  repeatedly emitting the same tool image or claiming it is visible.

## Temporary upload without keeping screenshots in the PR

This fallback was verified with this repository's GitHub connector. GitHub can
serve a file by its full commit SHA after that commit is removed from the branch.
It is not a first-class attachment API, and retention of unreachable objects is
not guaranteed. Prefer regular attachments when supported; verify this fallback
each time rather than promising permanent hosting.

- **SHOT-UPLOAD-01:** Start on the intended PR branch with a clean index and
  worktree. Record its original full HEAD SHA and confirm it matches the remote
  PR head. Preserve the original image in scratch storage. If the branch has
  unrelated work or someone else's newer commits, resolve that situation before
  proceeding; do not overwrite it.
- **SHOT-UPLOAD-02:** Copy only the PNG and its reproduction notes into
  `screenshots/`, stage those exact paths, create one temporary screenshot commit,
  record its full SHA, and push normally. Do not include application changes or
  unrelated files in this commit.
- **SHOT-UPLOAD-03:** After that push succeeds, remove only the temporary commit
  locally with `git reset --mixed ORIGINAL_HEAD`. Move the now-untracked PNG and
  notes back to scratch storage. Restore the remote branch with an explicit lease:

  ```bash
  git push --force-with-lease=refs/heads/BRANCH:TEMPORARY_COMMIT \
    origin ORIGINAL_HEAD:refs/heads/BRANCH
  ```

  Replace `BRANCH`, `TEMPORARY_COMMIT`, and `ORIGINAL_HEAD` with the recorded
  values. Never use bare `--force` or `reset --hard`. If the lease fails, inspect
  the new remote commits and preserve them; do not retry with a weaker lease.
- **SHOT-UPLOAD-04:** Use the full temporary commit SHA in the image URL:

  ```text
  https://github.com/OWNER/REPO/blob/TEMPORARY_COMMIT/screenshots/NAME.png?raw=true
  ```

  Verify this URL after removing the temporary commit, then embed it in the
  requested comment or description. Do not use the branch name, because its
  screenshot file has been removed.
- **SHOT-UPLOAD-05:** Verify the PR head is back at the original SHA, its changed
  files contain no screenshot artifacts, and the worktree is clean. Finish cleanup
  even if image verification or posting fails. Report an actual failure without
  posting a broken image link or leaving the temporary commit on the PR branch.

## File naming

- **SHOT-NAME-01:** Use `kebab-case.png`, named after the page and the state it captures:
  `<page>-<state>.png` (e.g. `feeds-empty-no-token.png`,
  `status-empty-draft-feeds.png`).
- **SHOT-NAME-02:** Append a qualifier for variants, e.g. `-mobile` for a narrow viewport.

## Annotation files

- **SHOT-META-01:** Give every `<name>.png` a matching `<name>.md` using this format:

  ```
  # <name>.png

  URL: `/path` (desktop, 1280px, full page)
  State: minimal conditions to reproduce the UI state
  Shows: the one thing the screenshot demonstrates
  ```

- **SHOT-META-02:** Describe only the minimal state needed to reproduce the screenshot
  (signed in or not, records present or not, which state a record is in).
  Omit record counts, names, exact copy, and lists of visible UI elements,
  since those drift as the app evolves.
