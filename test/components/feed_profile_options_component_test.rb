require "test_helper"
require "view_component/test_case"

class FeedProfileOptionsComponentTest < ViewComponent::TestCase
  # Covers every type the component renders, including ones no shipped profile
  # declares, so the rendering is pinned to the schema and not to a fixed list.
  TYPED_SCHEMA = {
    "type" => "object",
    "properties" => {
      "url" => { "type" => "string", "format" => "uri" },
      "fancy" => { "type" => "boolean", "title" => "Fancy mode", "description" => "Makes it fancy." },
      "flavour" => { "type" => "string", "title" => "Flavour" },
      "quality" => { "type" => "string", "enum" => %w[low high] }
    },
    "required" => ["url"],
    "additionalProperties" => false
  }.freeze

  def user
    @user ||= create(:user)
  end

  def feed(feed_profile_key: nil, **params)
    attrs = { user: user, params: { "url" => "https://example.com/feed.xml" }.merge(params) }
    attrs[:feed_profile_key] = feed_profile_key if feed_profile_key
    build(:feed, **attrs)
  end

  def render_typed(subject_feed = feed, profile_keys: [])
    FeedProfile.stub(:parameter_schema_for, ->(_key) { TYPED_SCHEMA }) do
      render_inline(FeedProfileOptionsComponent.new(feed: subject_feed, profile_keys: profile_keys))
    end
  end

  def labels(result)
    result.css("label").map { |label| label.text.strip }
  end

  test "#render should render a checkbox for a boolean option" do
    result = render_typed

    assert_not_nil result.css('[data-key="form.profile-option.fancy"]').first
    assert_not_nil result.css('input[type="checkbox"][name="feed[params][fancy]"]').first
    assert_includes labels(result), "Fancy mode"
    assert_includes result.to_html, "Makes it fancy."
  end

  test "#render should pair a boolean option with an unchecked-state input" do
    result = render_typed

    assert_not_nil result.css('input[type="hidden"][name="feed[params][fancy]"][value="0"]').first
  end

  test "#render should check a boolean option that is on" do
    result = render_typed(feed("fancy" => true))

    assert_not_nil result.css('input[type="checkbox"][name="feed[params][fancy]"][checked]').first
  end

  test "#render should leave a boolean option unchecked when it is off" do
    result = render_typed(feed("fancy" => false))

    assert_empty result.css('input[type="checkbox"][name="feed[params][fancy]"][checked]')
  end

  test "#render should render a text field for a string option" do
    result = render_typed(feed("flavour" => "vanilla"))

    assert_not_nil result.css('input[type="text"][name="feed[params][flavour]"][value="vanilla"]').first
    assert_includes labels(result), "Flavour"
  end

  test "#render should render a select for a string option with choices" do
    result = render_typed(feed("quality" => "high"))

    assert_not_nil result.css('select[name="feed[params][quality]"] option[selected][value="high"]').first
  end

  test "#render should title an option from its key when the schema has none" do
    assert_includes labels(render_typed), "Quality"
  end

  test "#render should skip the profile's own source param" do
    assert_empty render_typed.css('[name="feed[params][url]"]')
  end

  test "#render should render the Shorts option for a youtube feed" do
    subject = feed(feed_profile_key: "youtube", "url" => "https://www.youtube.com/@chan")

    result = render_inline(FeedProfileOptionsComponent.new(feed: subject))

    assert_not_nil result.css('input[type="checkbox"][name="feed[params][exclude_shorts]"]').first
    assert_includes labels(result), "Skip Shorts"
  end

  test "#render should render a panel per submittable profile" do
    result = render_inline(FeedProfileOptionsComponent.new(
      feed: feed(feed_profile_key: "youtube", "url" => "https://www.youtube.com/@chan"),
      profile_keys: %w[youtube rss]
    ))

    assert_equal 1, result.css('[data-profile-key="youtube"]').size, "rss declares no options"
    assert_not result.css('[data-profile-key="youtube"]').first.attributes.key?("hidden")
  end

  test "#render should hide and disable a profile the form hasn't selected" do
    result = render_inline(FeedProfileOptionsComponent.new(
      feed: feed(feed_profile_key: "rss"),
      profile_keys: %w[rss youtube]
    ))

    group = result.css('[data-profile-key="youtube"]').first
    assert group.attributes.key?("hidden"), "the unselected panel starts hidden"
    assert_equal [], group.css("input:not([disabled])").to_a, "its inputs can't submit"
  end

  test "#render should fall back to the feed's own profile" do
    result = render_inline(FeedProfileOptionsComponent.new(
      feed: feed(feed_profile_key: "youtube", "url" => "https://www.youtube.com/@chan")
    ))

    assert_not_nil result.css('[data-profile-key="youtube"]').first
  end

  test "#render? should be false for a profile declaring no options" do
    subject = FeedProfileOptionsComponent.new(feed: feed)

    assert_not subject.render?
  end

  test "#value_for should fall back to the schema default" do
    option = FeedProfile::ParamOption.new("fancy", { "type" => "boolean", "default" => true })

    assert_equal true, FeedProfileOptionsComponent.new(feed: feed).value_for(option)
  end
end
