# Screenshots

Reference screenshots of app pages in specific UI states. They document how a
page is supposed to look and let an agent retake the same screenshot after the
codebase changes.

## File naming

- `kebab-case.png`, named after the page and the state it captures:
  `<page>-<state>.png` (e.g. `feeds-empty-no-token.png`,
  `status-empty-draft-feeds.png`).
- Variants append a qualifier: `-mobile` for a narrow viewport, `-before` for a
  pre-change reference.

## Annotation files

Every `<name>.png` has a matching `<name>.md`:

```
# <name>.png

URL: `/path` (desktop, 1280px, full page)
State: minimal conditions to reproduce the UI state
Shows: the one thing the screenshot demonstrates
```

Keep annotations decoupled from the picture: describe only the minimal state
needed to reproduce the screenshot (signed in or not, records present or not,
which state a record is in) — not record counts, names, exact copy, or the
list of visible UI elements, since those drift as the app evolves.
