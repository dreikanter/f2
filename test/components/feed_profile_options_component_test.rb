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

  def render_typed(subject_feed = feed)
    FeedProfile.stub(:parameter_schema_for, ->(_key) { TYPED_SCHEMA }) do
      render_inline(FeedProfileOptionsComponent.new(feed: subject_feed))
    end
  end

  test "#render should render a checkbox for a boolean option" do
    render_typed

    assert_selector "[data-key='form.profile-option.fancy']"
    assert_selector "input[type=checkbox][name='feed[params][fancy]']"
    assert_selector "label", text: "Fancy mode"
    assert_text "Makes it fancy."
  end

  test "#render should pair a boolean option with an unchecked-state input" do
    render_typed

    assert_selector "input[type=hidden][name='feed[params][fancy]'][value='0']", visible: :all
  end

  test "#render should check a boolean option that is on" do
    render_typed(feed("fancy" => true))

    assert_selector "input[type=checkbox][name='feed[params][fancy]'][checked]"
  end

  test "#render should leave a boolean option unchecked when it is off" do
    render_typed(feed("fancy" => false))

    assert_no_selector "input[type=checkbox][name='feed[params][fancy]'][checked]"
  end

  test "#render should render a text field for a string option" do
    render_typed(feed("flavour" => "vanilla"))

    assert_selector "input[type=text][name='feed[params][flavour]'][value='vanilla']"
    assert_selector "label", text: "Flavour"
  end

  test "#render should render a select for a string option with choices" do
    render_typed(feed("quality" => "high"))

    assert_selector "select[name='feed[params][quality]'] option[selected][value='high']"
  end

  test "#render should title an option from its key when the schema has none" do
    render_typed

    assert_selector "label", text: "Quality"
  end

  test "#render should skip the profile's own source param" do
    render_typed

    assert_no_selector "input[name='feed[params][url]']", visible: :all
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
