require "test_helper"
require "view_component/test_case"

class CandidateOptionComponentTest < ViewComponent::TestCase
  def candidate(attributes)
    FeedIdentification::Candidate.new(attributes)
  end

  def render_option(attributes, input: "https://example.com/feed.xml", selected: nil, single: false)
    render_inline CandidateOptionComponent.new(
      candidate: candidate(attributes), input: input, selected: selected, single: single
    )
  end

  test "#render should mark a passed source as tested with its post count" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 3 })

    badge = result.at_css("[data-key='candidate.rss.status']")
    assert_equal "Tested · 3 posts", badge.text.strip
    assert_includes badge["class"], "green"
  end

  test "#render should singularize a single post" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 1 })

    assert_equal "Tested · 1 post", result.at_css("[data-key='candidate.rss.status']").text.strip
  end

  test "#render should note when a passed source has no posts yet" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 0 })

    assert_equal "Tested", result.at_css("[data-key='candidate.rss.status']").text.strip
    assert_match(/no posts yet/i, result.at_css("[data-key='candidate.rss.note']").text)
  end

  test "#render should give a failed source a red badge, an advisory, and a disabled radio" do
    result = render_option({ "profile_key" => "rss", "test_status" => "failed" })

    assert_includes result.at_css("[data-key='candidate.rss.status']")["class"], "red"
    assert result.at_css("[data-key='candidate.rss.note']").present?
    assert_not_nil result.at_css("input[type=radio][disabled]")
  end

  test "#render should give an unreachable source a yellow badge and advisory" do
    result = render_option({ "profile_key" => "rss", "test_status" => "unreachable" })

    assert_includes result.at_css("[data-key='candidate.rss.status']")["class"], "yellow"
    assert_match(/couldn't reach/i, result.at_css("[data-key='candidate.rss.note']").text)
  end

  test "#render should label an untested AI candidate as not tested with no note" do
    result = render_option({ "profile_key" => "llm_website_extractor", "test_status" => "not_tested" })

    assert_equal "Not tested", result.at_css("[data-key='candidate.llm_website_extractor.status']").text.strip
    assert_nil result.at_css("[data-key='candidate.llm_website_extractor.note']")
  end

  test "#render should omit the badge when the candidate carries no verdict" do
    result = render_option({ "profile_key" => "rss" })

    assert_nil result.at_css("[data-key='candidate.rss.status']")
  end

  test "#render should flag the selected candidate as recommended and check its radio" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 2 }, selected: "rss")

    assert_not_nil result.at_css("input[type=radio][checked]")
    assert_not_nil result.at_css("[data-key='candidate.recommended-badge']")
  end

  test "#render should not flag a disabled candidate even when it is the selected one" do
    result = render_option({ "profile_key" => "rss", "test_status" => "failed" }, selected: "rss")

    assert_nil result.at_css("[data-key='candidate.recommended-badge']")
    assert_not_nil result.at_css("input[type=radio][disabled]")
  end

  test "#render should lock a single candidate with no recommended badge and a disabled radio" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 2 }, selected: "rss", single: true)

    assert_nil result.at_css("[data-key='candidate.recommended-badge']")
    assert_not_nil result.at_css("input[type=radio][disabled]")
  end

  test "#render should surface the AI token-cost note for AI candidates" do
    result = render_option({ "profile_key" => "llm_website_extractor", "test_status" => "not_tested", "depends_on_ai" => true })

    assert_match(/costs AI tokens/i, result.at_css("[data-key='candidate.ai-cost']").text)
  end
end
