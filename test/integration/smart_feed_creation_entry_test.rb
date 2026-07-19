require "test_helper"

# The creation-mode entry on the new-feed page (spec 005 §1, webhook mode per
# spec 006 §7): radios carry the mechanism, all panels render server-side, and
# only the selected mode's panel is visible.
class SmartFeedCreationEntryTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "#new should render all modes with the link mode selected" do
    sign_in_as(user)

    get new_feed_path

    assert_response :success
    assert_select "[data-key='entry.mode-link'] input[type=radio][value=link][checked]"
    assert_select "[data-key='entry.mode-ai'] input[type=radio][value=ai]:not([checked])"
    assert_select "[data-key='entry.mode-webhook'] input[type=radio][value=webhook]:not([checked])"
    assert_select "[data-key='entry.panel-link']:not([hidden])"
    assert_select "[data-key='entry.panel-ai'][hidden]"
    assert_select "[data-key='entry.panel-webhook'][hidden]"
    # The radio label is the group's single visible label; the field keeps its
    # name for assistive tech only.
    assert_select "input#entry-link-input[name='url'][aria-label='Source link']"
    assert_select "label[for='entry-link-input']", count: 0
  end

  test "#new with mode=webhook should select the webhook mode" do
    sign_in_as(user)

    get new_feed_path(mode: "webhook")

    assert_response :success
    assert_select "[data-key='entry.mode-webhook'] input[type=radio][checked]"
    assert_select "[data-key='entry.mode-link'] input[type=radio]:not([checked])"
    assert_select "[data-key='entry.panel-webhook']:not([hidden])"
    assert_select "[data-key='entry.panel-link'][hidden]"
    assert_select "[data-key='entry.panel-webhook'] form input[type=hidden][name='webhook']"
  end

  test "#new with mode=ai should select the AI mode" do
    sign_in_as(user)

    get new_feed_path(mode: "ai")

    assert_response :success
    assert_select "[data-key='entry.mode-ai'] input[type=radio][checked]"
    assert_select "[data-key='entry.mode-link'] input[type=radio]:not([checked])"
    assert_select "[data-key='entry.panel-ai']:not([hidden])"
    assert_select "[data-key='entry.panel-link'][hidden]"
    assert_select "textarea#entry-ai-input[name='prompt'][aria-label='What should AI follow?']"
    assert_select "label[for='entry-ai-input']", count: 0
  end

  test "#new with an unknown mode should fall back to the link mode" do
    sign_in_as(user)

    get new_feed_path(mode: "bogus")

    assert_response :success
    assert_select "[data-key='entry.mode-link'] input[type=radio][checked]"
    assert_select "[data-key='entry.panel-link']:not([hidden])"
    assert_select "input#entry-link-input[name='url']"
  end

  test "#new should keep the modes' forms separate" do
    sign_in_as(user)

    get new_feed_path

    # Independent forms: the radios are disclosure only and never submit.
    assert_select "[data-key='entry.panel-link'] form input[name='url']", count: 1
    assert_select "[data-key='entry.panel-ai'] form textarea[name='prompt']", count: 1
    assert_select "[data-key='entry.panel-webhook'] form input[name='webhook']", count: 1
    assert_select "form input[name='entry_mode']", count: 0
  end

  test "#new should default the AI textarea to the 2000-char prompt ceiling" do
    sign_in_as(user)

    get new_feed_path(mode: "ai")

    assert_select "textarea#entry-ai-input[maxlength='2000']"
  end
end
