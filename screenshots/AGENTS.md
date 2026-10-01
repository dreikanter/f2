# Screenshots

Reference screenshots of app pages in specific UI states. They document how a
page is supposed to look and let an agent retake the same screenshot after the
codebase changes.

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
