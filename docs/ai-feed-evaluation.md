# Local AI feed evaluation

`bin/ai-feed-eval` runs the real feed preview pipeline with the application's
stored OpenAI credential. It does not create a FreeFeed post. Cases live in
`config/ai_feed_evaluation_cases.yml`. A dry run writes the prompt, schema,
settings, and code revision without calling OpenAI:

```sh
mise exec -- ruby bin/ai-feed-eval --case x_today --model gpt-5-nano
```

Add `--live` to spend money. Set `--max-spend-usd`, `--max-requests`,
`--max-search-calls`, `--max-output-tokens`, `--max-total-tokens`, and
`--iterations` for a bounded run. Use `--baseline PATH` to compare with an
earlier JSON report. The command writes complete prompts, schema, saved
conversation and tool records, preview outcomes, UID decisions, usage, errors,
and known costs to a local JSON report. It never writes an API key.

The spend limit is a conservative preflight estimate using the model context
window and supplied native search price. Token use is checked after each
provider response. OpenAI has returned an extra tool call beyond a requested
call limit in a local run, so an in-flight request can exceed an observed
limit. A run with incomplete usage reports unknown cost and stops further
iterations. The command is therefore a spending guard, not an exact billing
cap.

## Acceptance criteria

Assess each run against its request, rather than treating a nonempty result or
a completed API request as success:

| Dimension | Pass condition |
| --- | --- |
| Grounding | Retrieved posts have direct, inspectable evidence for text, author, permalink, and any claimed engagement. No invented source content. |
| Relevance | Each candidate meets the topic and substance requirements. |
| Time | Relative dates use one recorded reference time and timezone. Source publication falls inside the requested window; retrieval and processing times do not substitute for it. |
| Identity | The same source post keeps one normalized UID across discovery and retry; generated content follows a documented retry identity rule. |
| Format | Published body follows the request's length, quoting, summary, and comment rules. |
| Outcome | Empty runs identify the observed stage and retain uncertainty where provider evidence is missing. Duplicate candidates remain distinguishable from retrieval failures. |
| Execution | Latency, requests, tool calls, tokens, and known and unknown charges stay within the stated experimental limits. |

The `x_today`, `developer_news`, and `x_any_date` cases exercise retrieval.
`original_tip`, `stoic_quote`, and `legitimate_empty` are held out from prompt
tuning. A Stoic quote has no natural permalink, so quote identity requires a
separate policy before claiming that the feed can avoid variants or repeats.

## Initial observations

The supplied September 24 case returned `{"items":[]}` after seven native
search calls, but its log did not show consulted source URLs. The local database
had no saved LLM chats from that session, so the original provider response
could not be inspected here.

Local `gpt-5-nano` preview runs on September 26 reproduced an empty X-today
answer. A baseline with one request, four native calls, and 4096 output tokens
searched X broadly and opened X's search page. It returned zero candidates in
14.7 seconds. A less date-constrained X case found an individual older post
permalink, then exhausted its output limit before producing a candidate. These
runs show that strict publication-date verification matters, but do not prove
that no qualifying X post existed.

After requesting `web_search_call.action.sources`, a further X-today run
recorded the URLs consulted by completed searches: the first search listed
fourteen URLs, including AI news and X aggregator pages; the second listed
twelve X help, blog, business, and partner pages. None was an individual
`x.com/<handle>/status/<id>` post. The model opened an aggregator twice and
then attempted another search. It produced no validated candidate and exceeded
the configured native-call limit. The observed proximate failure is lack of
an inspected, date-verifiable source post in this run. The source list is the
provider's consulted URLs, not a complete ranking of all available results.

One `gpt-5-mini` run with the same X-today prompt did surface individual X
status URLs in search sources, then opened X's search page instead of an
individual post. It never established the text and source publication time of
a qualifying post. The run made five native calls against a requested limit
of four and failed after 31.1 seconds, with incomplete final-call usage.
Changing from `gpt-5-nano` to `gpt-5-mini` therefore did not pass the case in
this single comparison. It does show that discovery and candidate inspection
are distinct failure points.

A separate original Rails-tip case completed with one preview item and no
search calls using a 4096 output-token cap. At 1024 output tokens, the same
case hit the output limit without a final answer. This supports keeping
execution limits high enough for reasoning and schema completion even when the
requested body is short. It does not establish repeatability or quality across
models and prompts.

The held-out Stoic quote case searched two common Marcus Aurelius quotations
and hit the 4096 output-token cap without a final answer. Its request to avoid
past quotes cannot be verified by the model because the feed prompt does not
include prior quote identities. The search record supports the output-limit
finding; it does not establish which quotation would have been returned.

No prompt candidate improved the X case in the bounded local trials, so no
prompt change is included here. Future live tests should repeat a promising
result, compare it to this baseline, and use held-out cases before changing
the production prompt. The remaining work includes stable identity for
generated content, deterministic date and deduplication checks, and distinct
diagnostic outcomes for empty runs.
