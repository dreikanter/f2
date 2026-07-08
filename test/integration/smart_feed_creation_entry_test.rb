require "test_helper"

# The two-mode entry on the new-feed page (spec 005 §1): tabs carry the
# mechanism as real links, and the server renders the active mode's field.
class SmartFeedCreationEntryTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "#new should render the link entry with tabs to both modes" do
    sign_in_as(user)

    get new_feed_path

    assert_response :success
    assert_select "[data-key='entry.mode-link'][aria-current='page']", text: "Follow a feed or channel"
    assert_select "[data-key='entry.mode-ai']:not([aria-current])", text: "Follow with AI"
    assert_select "[data-key='entry.mode-ai'][href='#{new_feed_path(mode: "ai")}']"
    assert_select "label[for='entry-link-input']", text: "Source link"
    assert_select "input#entry-link-input[name='url']"
    assert_select "textarea#entry-ai-input", false
  end

  test "#new with mode=ai should render the AI entry" do
    sign_in_as(user)

    get new_feed_path(mode: "ai")

    assert_response :success
    assert_select "[data-key='entry.mode-ai'][aria-current='page']", text: "Follow with AI"
    assert_select "[data-key='entry.mode-link']:not([aria-current])", text: "Follow a feed or channel"
    assert_select "[data-key='entry.mode-link'][href='#{new_feed_path}']"
    assert_select "label[for='entry-ai-input']", text: "What should AI follow?"
    assert_select "textarea#entry-ai-input[name='prompt']"
    assert_select "input[type='hidden'][name='mode']", false
    assert_select "input#entry-link-input", false
  end

  test "#new with an unknown mode should fall back to the link entry" do
    sign_in_as(user)

    get new_feed_path(mode: "bogus")

    assert_response :success
    assert_select "[data-key='entry.mode-link'][aria-current='page']"
    assert_select "input#entry-link-input[name='url']"
  end

  test "#new should default the AI textarea to the 2000-char prompt ceiling" do
    sign_in_as(user)

    get new_feed_path(mode: "ai")

    assert_select "textarea#entry-ai-input[maxlength='2000']"
  end
end
