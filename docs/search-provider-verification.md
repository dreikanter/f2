# Verifying a web search provider

`WebSearchProvider` turns three vendor APIs into one normalized interface. Its
unit tests run against fixtures, which can only confirm our reading of a
vendor's docs — not that the vendor still behaves that way. `SearchCapabilityProbe`
closes that gap by talking to the live API.

Run it before trusting a new provider, and again when a vendor announces API
changes or when search starts failing in a way the logs don't explain.

## Running it

Each provider has its own job: `SerperCapabilityProbeJob`,
`BraveCapabilityProbeJob`, `TavilyCapabilityProbeJob`. Open `/development/jobs`,
pick one, and run it. Each check writes one event with its evidence, plus a
summary verdict, so the run page is the whole record.

The key comes from a managed credential, not the environment: the probe uses the
`SearchCredential` whose name matches the probe — **Serper Probe**, **Brave
Probe**, **Tavily Probe** — with the matching provider, owned by a user with the
`dev` permission. Without that record the run records a skip saying which
credential to create; if two dev users hold the same probe name, it refuses
rather than pick one. The credential does not have to be active; probing a
rejected key is a legitimate thing to want.

Two of the three checks spend a real query, billed to that credential and
recorded as usage like any other search.

## What it checks, and why only these

| Check | What it proves |
| --- | --- |
| `rejection` | An invalid key comes back as `AuthError`. Free, and the one check fixtures can't stand in for |
| `search` | A live query returns results that still map to populated `Result` fields |
| `minimal` | The one-result query `SearchCredentialValidationJob` sends is accepted |

`rejection` is the check worth understanding. Classification is per-vendor
(`Base#auth_error?`): Serper rejects a key with 403, Brave with 422 plus an
error code in the body, Tavily reports an exhausted key with 432/433. Get it
wrong and a dead key reads as a passing fault — the credential stays active, the
feed stays enabled, and every refresh keeps calling a key that can never work.
That failure is invisible to fixtures, because the fixtures encode the same
assumption the code does.

A `FAIL` on `search` with a live key usually means the vendor renamed a response
field: the mapping in `map_results` silently produces nothing, which in
production looks identical to a query with no matches. The event's evidence
carries the results as mapped, so the fix is normally visible in the diff
between that and the vendor's current response shape.
