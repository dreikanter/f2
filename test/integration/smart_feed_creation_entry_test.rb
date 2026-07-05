require "test_helper"

# The two-mode entry on the new-feed page (spec 005 §1): a mode toggle carries
# the mechanism, and each mode has its own labelled field.
class SmartFeedCreationEntryTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "#new should render the mode toggle with both entry fields" do
    sign_in_as(user)

    get new_feed_path

    assert_response :success
    assert_select "[data-key='entry.mode-link']", text: "Follow a feed or channel"
    assert_select "[data-key='entry.mode-ai']", text: "Follow with AI"
    assert_select "label[for='entry-link-input']", text: "Source link"
    assert_select "input#entry-link-input[name='input']"
    assert_select "label[for='entry-ai-input']", text: "What should AI follow?"
    assert_select "textarea#entry-ai-input[name='input']"
    assert_select "input[type='hidden'][name='mode'][value='ai']"
  end

  test "#new should default the AI textarea to the 2000-char prompt ceiling" do
    sign_in_as(user)

    get new_feed_path

    assert_select "textarea#entry-ai-input[maxlength='2000']"
  end
end
