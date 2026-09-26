# AI feed identity

Retrieved source posts use a UID derived from their source permalink. The URL
resolver converts HTTP to HTTPS, lowercases the host, removes a leading `www.`,
default ports, fragments, a trailing slash, and common tracking parameters.
Other path and query content remains part of the identity.

Generated items with no source URL use `generated:` plus SHA-256 of the
generation ID and item position. A feed refresh job uses its job ID as the
generation ID, so retrying that job keeps each item UID even if its wording
changes. A new scheduled or manual job has a new ID and can publish new
content, including identical wording. A preview uses its preview run ID;
direct workflow runs use a fresh ID. Feed entry UIDs are scoped to a feed.

This policy prevents duplicate publication on retries of the same job. It
does not deduplicate identical wording across separate generations, paraphrases,
alternate Stoic translations, or the same source post under materially
different URLs. Those need a separate quote or source identity policy before
promising full non-repetition.
