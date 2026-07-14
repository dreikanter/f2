# Changelog

User-facing changes, newest first. Internal/technical changes are not listed here.

## 2026-07-14

- AI feeds now use their selected managed search-provider key consistently across every AI provider.
- AI feeds now let you choose a managed search-provider key alongside the AI provider and model; setup points directly to whichever credential type is still missing.
- You can now add, check, rename, choose a default, and remove search-provider API keys from a dedicated Search Credentials settings page.

## 2026-07-13

- AI usage stats on feed pages now cover the last 30 days instead of all time, so the numbers reflect recent activity.

## 2026-07-11

- Disabled feeds are easier to spot in your feed list: their pause icon is now orange instead of gray.
- Feed refresh entries in the events log now show what each AI run cost — the estimated spend appears next to the entry, and the event page breaks it down per AI call.
- Posts with an image over FreeFeed's upload size limit now publish without that image instead of failing entirely.

## 2026-07-10

- You can now catch up on what's new right in the app: there's a Changelog page in your account menu.
- You can now follow Bluesky accounts: paste a bsky.app profile link, and their posts get reposted with pictures included.
- Admin feed pages now match regular feed pages: empty Recent Activity and Recent Posts sections stay hidden, and heading spacing is consistent.
- Enabling an AI feed that's missing a working AI credential or a model now explains what's left to set up instead of failing with an error page.
