# Changelog

User-facing changes, newest first. Internal/technical changes are not listed here.

## 2026-07-06

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
