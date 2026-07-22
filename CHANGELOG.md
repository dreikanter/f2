# Changelog

User-facing changes, newest first. Internal/technical changes are not listed here.

## 2026-07-22

- Picking Refresh from a feed's actions menu now closes the menu and confirms the refresh has started, instead of leaving you guessing whether the click did anything.
- Token pages and post previews now show your actual FreeFeed userpic instead of the generic placeholder. Newly validated tokens pick it up automatically.
- Turning on a feed now always requires a working FreeFeed access token. Previously the feed page's Enable button checked this, but saving the feed with "Enable feed" turned on did not.
- When a feed's access token stops working, the feed page's Enable button now says exactly what's missing, and the feed's settings explain that saving will switch it to one of your working tokens.
- Trimmed the redundant "Showing" from event summaries and list counters — they now read like simple labels, e.g. "System-wide most recent events".

## 2026-07-21

- The prompt to add a FreeFeed access token on the feed form dropped its key icon, so everything now lines up along the same left edge.
- The access tokens page now shows only your own tokens. Admins previously saw everyone's tokens there and could open or edit them.
- Copy buttons now confirm with a crisp checkmark icon that matches the rest of the interface, instead of a plain text tick.
- Warning and error events no longer highlight whole rows in amber and red — severity now shows in the icon's color, keeping activity lists calmer to scan.
- Events in activity lists now carry icons that match what happened — an envelope for email events, arrows for feed refreshes — instead of a generic severity marker.
- Access token pages no longer show an empty "Associated Feeds" section when no feeds use the token.
- Inactive feeds can now be deleted right from the feeds list — handy when a feed's access token is gone and the feed has nowhere left to go.
- The "Enable feed" option now stays off with a note about what's missing — like a FreeFeed token or AI credentials — instead of failing with an error that didn't point anywhere.
- The Invites page now shows only your own invitations. Admins previously saw everyone's invites there, including the one they signed up with.
- Empty state placeholders now look the same on phones as on larger screens — rounded corners, comfortable spacing, and softer gray text.
- The default userpic no longer flickers between white and gray backgrounds on token and post pages.
- The sign-in page now keeps your email address in place after a wrong password, so you only need to retype the password.
- "Back to sign in" links are now a bit taller, making them easier to tap.
- The "Back to sign in" link on the password reset pages now lines up on the left on small screens, like on the other pages.

## 2026-07-20

- Timestamps in event details, like "Started at" and "Completed at", now show how long ago they happened — "20 Jul 2026, 20:00 (48m)" — matching the rest of the page.
- Post pages now show the post the way it appears on FreeFeed — author and group up top, then the text, images, and comments in one card.
- Admins can now open read-only pages for any user's access tokens, AI credentials, and search credentials straight from the events log.
- Reddit posts no longer show raw character codes like `&#8217;` in titles — they come through as the intended characters.
- Admin user pages now show the user's recent activity with a link to their full events log.
- Filtered event logs now describe the filter in plain words — "Filtering by Feed [ce23f]" — with a link to the feed, user, or other entity you're filtering by.
- Draft feeds no longer show an empty Stats section — it appears once the feed is up and running.
- Event pages now show refresh stats right in the details list at the top instead of a separate Stats section.
- The admin Feeds page now explains that it lists feeds from all users.
- The "Follow with AI" option on the new feed page now carries a "Beta" badge, so it's clear the feature is still settling in.
- The access token page now shows the groups you can post to right away, without a click to expand the list.

## 2026-07-19

- Webhook feed setup now asks you to choose a name and uses clearer progress messages.
- Webhook feeds now hide options that only apply to feeds checked on a schedule.
- Menu items in the mobile navigation are now taller, making them easier to tap.

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
- AI-powered previews now get more time to finish — up to about four minutes, since they browse the web — so a slow one no longer gets cut off early, and the progress note says what's happening. A preview that does time out now stays timed out instead of quietly flipping to done after you've moved on.

## 2026-07-06

- You can now edit an AI feed's prompt after it's running, not just while it's a draft — with a heads-up that reworking it may pull in some older posts.
- A greyed-out Preview button now tells you what's still missing — a source, an AI provider, or a model — instead of just sitting there.
- Changing a feed's source or type while editing now flags whether it might repost items you've already seen — and a type change switches on "Skip older posts" by default so recent ones don't flood back in.
- You can now change a feed's source link when editing it. We re-check the new link for a feed before saving, so a broken link can't quietly slip in — and the feed keeps running on its current source until the new one checks out.
- If an AI feed's model is no longer available, the feed keeps running on a supported fallback and flags it on the feed page, instead of blocking edits or quietly using the missing one. Pick a new model whenever you're ready.

## 2026-07-05

- Added Moonshot (Kimi) as an AI provider — a lower-cost option you can connect with your own API key.
- Paste a bare address like `example.com` and we'll treat it as a link and check it for a feed. When a link has no standard feed, you can now choose to follow it with AI instead.
- New feeds now start with a clear choice: follow a feed or channel by its link, or follow with AI by describing a source or topic in your own words.
- When a link can't be followed, the next step is clearer: retry if it just couldn't be reached, or follow it with AI (or try a different link) when there's no feed to read.
- The "how should we fetch posts?" step is tidier: it only asks you to choose when more than one way actually works, and a single working option is just shown to you.
- Creating an AI feed now lets you tweak the prompt before saving, and it checks for new posts once a day by default.
- You can keep editing an AI feed's prompt while it's still a draft, not just when you first create it.

## 2026-07-03

- Fixed a refresh failure when a feed served the same item twice in one batch, which could wrongly disable the feed.

## 2026-06-26

- JSON feeds are now supported.
- AI-powered feeds now let you pick the AI provider and model right in the feed settings, with the model list updating to match the provider you choose.
- Previewing an AI feed now uses the exact provider and model you picked, and preview stays unavailable until a model is set.
- If an AI feed's chosen model is no longer available, the feed setup now flags it so you can pick a new one before enabling.

## 2026-06-25

- When adding a feed, each fetch option now shows its test result.
- Fixed the Cancel button not working while a new feed is being checked.

## 2026-06-23

- A feed you saved without turning on can now be enabled straight from the feed page or the feeds list.
- Editing a feed now shows its feed type, with a clearer note that the source and type stay fixed once a feed is created.
- Feed and post pages now keep extra actions in a dropdown menu.
- Settings now shows your permissions right under the page title.
- The Invites page now shows each invite as a card.
- Starting a feed without a FreeFeed token now shows a clear prompt to add one, instead of an empty token field and group picker.
- The "Add FreeFeed token" button now disables itself while saving, so a double-click can't submit twice.
- Use cards presentation for Change email and Change password on the Settings page.
- The access token page now shows an arrow next to the groups list, making it clear you can expand it.
- After you add a token, the dashboard now points you to create your first feed.
- Feeds and Posts are now reachable while you're still setting up, instead of staying hidden until later.
- The Feeds and Posts pages now explain what they're for right in the header.
- When you don't have any feeds yet, the Posts page points you to add your first one.
- Fixed password reset emails not being sent to some confirmed accounts.

## 2026-06-22

- Clarified the feed Purge confirmation: it only removes posts this feed published, not the whole group.
- Feed list rows now show the number of published posts per feed.
- Delete actions now consistently end with "…" to signal they'll ask you to confirm first.
- Removed a redundant "back" button from the access token page — the breadcrumb already links back.
- Feed list rows now show each feed's status, and hide activity times for drafts.
- Settings now has quick links to Access Tokens, AI Credentials, and Invites, and each of those pages links back to Settings.
- Settings page now shows clearer permission names, like "Developer Tools" instead of "Dev".
- Feed pages now always show the Stats section, dimming zero and empty values until there's data.
- AI credential pages list available models in alphabetical order by provider and name.

## 2026-06-21

- Access tokens and AI credentials now use the same compact list layout as feeds.
- Fixed RSS posts attaching the same image twice when it appeared as both a cover and inline image.
- Improve New feed form layout: keeps source input on top, and labels it "Source URL" or "Source prompt" to match user entry.
- Refreshed the favicon with a bold fff ligature on Freefeed-orange tile.
- Refreshed the feed list with a cleaner, more compact card layout.
- Unified posts, feeds, and activity lists into a lighter, more compact look across the app.

## 2026-06-20

- AI credential pages now list the models each key can use.
- New feed option to import only posts that include images.
- Event pages now show stats in a clear, always-visible section.
- Started keeping a changelog of user-facing changes.
- New favicon featuring the Feeder mark.
