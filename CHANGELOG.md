# Changelog

User-facing changes, newest first. Internal/technical changes are not listed here.

## 2026-07-18

- New "Post via webhook" feed type: publish posts from your own scripts through a webhook endpoint and secret authorization token — a single curl command is enough. Images, comments, and safe retries are supported.

## 2026-07-17

- Fixed a security hole where non-admins could grant themselves invites or change their email through admin-only actions.
- Admins changing a user's email with confirmation required now correctly send the confirmation link to the new address.
- If FreeFeed temporarily rate-limits a post comment, publishing now pauses and resumes from that comment later without duplicating the post or earlier comments. Other comment errors keep the post published, continue the feed, and appear in Recent Activity.

## 2026-07-15

- The Admin Panel now shows app-wide stats — users, feeds, imported and published posts — along with a publishing activity heatmap.

## 2026-07-14

- Search credential and feed pages now show recent search-call counts and estimated search-provider spend.
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
- Telegram feeds now tell you clearly when a channel has no public web preview (restricted, private, or not a channel), instead of quietly showing no posts.
- Your events log now shows when a feed refresh is in progress; the entry is replaced by the result once the refresh finishes.

## 2026-07-09

- Choosing between following a feed or following with AI now uses a simple two-option choice that stays readable on small screens, where the old tabs used to stack awkwardly.
- Checking a link now happens right in the new-feed form instead of swapping it for a separate card: the form freezes while checking and comes back with a clear hint if something goes wrong. If your text isn't a link, it's already waiting in the AI option — just switch over and continue.
- Editing a feed's source works the same way: the form stays put while the new link is checked, with feedback right under the field.
- Once you've picked a model for a feed, the "Select a model…" placeholder can't be chosen anymore — a feed can't be switched back to having no model.
- Feed pages are less cluttered: the Recent Activity and Recent Posts sections only appear once there's something to show.
- A feed that hasn't refreshed yet shows a dash in its stats instead of "Never".
- Status badges now share one consistent look everywhere — softer colors with a subtle outline, the same style on feed, post, and admin pages.

## 2026-07-08

- Long source URLs and UIDs on post pages no longer spill outside the page — they're neatly cropped with an ellipsis, and hovering a cropped UID shows the full value.
- Event stats are easier to read: big numbers now use thousands separators, and step timings show as seconds and minutes instead of raw values.
- Choosing between following a link or following with AI on the new-feed page now uses tabs, so each option gets its own address you can bookmark or share.
- Fixed Moonshot (Kimi) API key checks: they used to fail with an error and leave the key stuck in "validating" — now they go through like the other providers.
- An API key check that can't reach the provider no longer leaves the key stuck in "validating" — it's marked as failed with the error, so you can try again.

## 2026-07-07

- AI feeds are steadier and safer: they now treat the pages they read as data rather than instructions to follow, and won't invent posts when a source turns up nothing — an empty check just brings in nothing.
- A daily AI digest feed no longer wastes AI calls re-checking within the same day — once its digest is in, extra scheduled runs are skipped until the next day. Hitting Refresh yourself still runs it right away.
- AI feeds can follow standing queries and roundups that don't have a single link — these come through as one digest post per day that cites its sources inline, instead of being dropped.
- AI feeds are steadier about not repeating or dropping posts: a link that only differs by `http`/`https`, `www`, or a port no longer counts as a new post, and posts with non-Latin links (like Cyrillic) come through instead of quietly disappearing.

## 2026-07-06

- You can now edit an AI feed's prompt after it's running, not just while it's a draft — with a heads-up that reworking it may pull in some older posts.
- A greyed-out Preview button now tells you what's still missing — a source, an AI provider, or a model — instead of just sitting there.
- Changing a feed's source or type while editing now flags whether it might repost items you've already seen — and a type change switches on "Skip older posts" by default so recent ones don't flood back in.
- You can now change a feed's source link when editing it. We re-check the new link for a feed before saving, so a broken link can't quietly slip in — and the feed keeps running on its current source until the new one checks out.
