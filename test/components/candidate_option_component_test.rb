require "test_helper"
require "view_component/test_case"

class CandidateOptionComponentTest < ViewComponent::TestCase
  def candidate(attributes)
    FeedIdentification::Candidate.new(attributes)
  end

  def render_option(attributes, input: "https://example.com/feed.xml", selected: nil)
    render_inline CandidateOptionComponent.new(
      candidate: candidate(attributes), input: input, selected: selected
    )
  end

  test "#render should mark a passed source as tested with its post count" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 3 })

    badge = result.at_css("[data-key='candidate.rss.status']")
    assert_equal "Tested · 3 posts", badge.text.strip
    assert_includes badge["class"], "bg-success-subtle"
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

  test "#render should render a selectable radio for every option" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 2 })

    assert_nil result.at_css("input[type=radio][disabled]")
  end

  test "#render should flag the selected candidate as suggested and check its radio" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 2 }, selected: "rss")

    assert_not_nil result.at_css("input[type=radio][checked]")
    assert_not_nil result.at_css("[data-key='candidate.suggested-badge']")
  end

  test "#render should not flag an unselected candidate as suggested" do
    result = render_option({ "profile_key" => "rss", "test_status" => "passed", "posts_found" => 2 }, selected: "xkcd")

    assert_nil result.at_css("[data-key='candidate.suggested-badge']")
  end
end
