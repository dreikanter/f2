# Code quality report

`bin/critic` runs [RubyCritic](https://github.com/whitesmith/rubycritic) (flay +
flog + reek + churn) over `app` and `lib` and summarises it. It is advisory and
local-only — CI does not run it and nothing gates on the score.

```sh
bin/critic                  # summary + duplication spanning files
bin/critic --all            # also rank files by duplication mass
bin/critic --raw            # RubyCritic's own console report
bin/critic app/components   # scope to given paths
```

In a remote Claude Code environment, run it in the container:
`docker compose exec app bin/critic` (see [claude-remote-env.md](claude-remote-env.md)).

## Why it earns its place

RuboCop runs rails-omakase, which disables every `Metrics/*` cop. Nothing else
in the toolchain reports duplication or complexity, so this axis is entirely
additive rather than a second opinion on style.

## What the output means

The headline score and letter grades are decoration — treat them as a trend,
not a target. `Findings by type` is worth a glance. The section that has
actually produced work is **duplication spanning files**: when two or three
classes appear in one group, they are usually near-clones that want a shared
base.

Duplication *within* one file is much weaker signal — often a deliberate
sequence of similar branches — which is why the default output only reports
groups that cross a file boundary.

`--all` ranks by duplication mass rather than complexity on purpose. The
highest-complexity files (`Feed`, `FeedRefreshWorkflow`) are large because the
work they do is large; they want decomposition, which is a design conversation
no report can hand you.

## Noise filtering

`.reek.yml` disables eight detectors that fire constantly on ordinary Rails
code. Without it the report is ~1700 findings; with it, ~340. Each entry in
that file records why it is off. For a one-off dig with a detector re-enabled,
pass a different config to `reek -c` rather than editing it.

## Known false positives

Findings already investigated and dismissed. Please don't spend time
re-deriving these:

- **`FeedProfile`, duplication 735** — the largest number in the report, and the
  weakest signal. It is the 21-entry profile registry. Registries are supposed
  to look repetitive; a builder DSL would trade legible declarative data for
  indirection.
- **`CredentialNameGenerator`, duplication 206** — flay comparing the
  `ADJECTIVES` and `NOUNS` word lists to each other.
- **`StatsPanelComponent`, duplication 84** — the mobile/desktop symmetry inside
  the base. That duplication used to be spread across four components; having it
  in one place is the improvement, not a regression.
- **`UnusedParameters` on abstract bases** — `HttpClient::Base`,
  `EmailStorage::Base` and friends declare a signature and raise. That is the
  point.
- **`AccessTokensController` vs `CredentialsController`**, and
  **`AccessTokenListItemComponent`** against the credential rows — access tokens
  share the shape but not the rules (owner-only, no admin reach; delete via
  modal, no default badge). Folding them together was considered and rejected.
- **`EventPolicy::Scope` vs `CredentialPolicy::Scope`** — identical bodies,
  unrelated permissions. Sharing them needs a module rather than a base class;
  still open, but small.

## Burned down so far

The credential family — controllers, policies, list rows, defaults controllers,
validation polling, and the models themselves — was collapsed onto shared bases
in #1204 and #1225–#1231. Score went 82.5 → 87.6, F-rated files 9 → 3.

Remaining cross-file groups cluster in the loaders, the normalizers, the
`WebSearchProvider` adapters, and a few controller pairs around email
confirmation and sessions. None have been sized.
