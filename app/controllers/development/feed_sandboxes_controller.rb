class Development::FeedSandboxesController < ApplicationController
  # A made-up source URL for the chooser previews. Only AI-search candidates
  # interpolate the input and none of the examples use one, so the value is
  # purely cosmetic.
  SAMPLE_INPUT = "https://example.com/feed.xml"

  def show
    authorize :access, :dev?
    @states = Development::SampleFeedsController::STATES
    @chooser_input = SAMPLE_INPUT
    @chooser_examples = chooser_examples
  end

  private

  # Hand-built candidate lists fed to the real feeds/_candidate_chooser partial
  # so every detection and self-test verdict can be eyeballed in one place. The
  # verdict fields (test_status/posts_found) are ignored by the chooser until
  # the self-test UI lands, at which point these previews light up automatically.
  def chooser_examples
    [
      {
        title: "Single source, locked in",
        note: "Only one way to fetch this source, so it's preselected and can't be changed.",
        single: true,
        candidates: [candidate("rss", test_status: "passed", posts_found: 5)]
      },
      {
        title: "Working source with an AI fallback",
        note: "A source that passed its test is suggested; the AI reader is offered as a backup.",
        candidates: [
          candidate("rss", test_status: "passed", posts_found: 5),
          candidate("llm_website_extractor", depends_on_ai: true, test_status: "not_tested")
        ]
      },
      {
        title: "Works, but nothing to show yet",
        note: "The test passed but the source has no posts at the moment.",
        candidates: [
          candidate("rss", test_status: "passed", posts_found: 0),
          candidate("llm_website_extractor", depends_on_ai: true, test_status: "not_tested")
        ]
      },
      {
        title: "Source failed, AI takes over",
        note: "The structured source couldn't be read, so it's disabled and the AI reader is suggested.",
        candidates: [
          candidate("rss", test_status: "failed", posts_found: 0),
          candidate("llm_website_extractor", depends_on_ai: true, test_status: "not_tested")
        ]
      },
      {
        title: "Source couldn't be reached",
        note: "A working source is suggested; the unreachable one stays pickable in case it was a temporary blip.",
        candidates: [
          candidate("rss", test_status: "passed", posts_found: 3),
          candidate("xkcd", test_status: "unreachable")
        ]
      },
      {
        title: "Every verdict together",
        note: "Passed, failed, unreachable, and an untested AI option side by side.",
        candidates: [
          candidate("rss", test_status: "passed", posts_found: 4),
          candidate("youtube", test_status: "failed"),
          candidate("xkcd", test_status: "unreachable"),
          candidate("llm_website_extractor", depends_on_ai: true, test_status: "not_tested")
        ]
      }
    ]
  end

  def candidate(profile_key, depends_on_ai: false, test_status: nil, posts_found: 0)
    {
      "profile_key" => profile_key,
      "title" => FeedProfile.display_name_for(profile_key),
      "depends_on_ai" => depends_on_ai,
      "test_status" => test_status,
      "posts_found" => posts_found,
      "rank" => 0,
      "rank_reason" => depends_on_ai ? "ai_fallback" : "specific_match"
    }
  end
end
