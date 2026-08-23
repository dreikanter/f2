require "test_helper"

class CredentialHelperTest < ActionView::TestCase
  def user
    @user ||= create(:user)
  end

  test "#access_token_status_badge should label an active token valid" do
    access_token = create(:access_token, :active, user: user)

    badge = render_inline_badge(access_token_status_badge(access_token))

    assert_equal "Valid", badge.text
    assert_equal "active", badge["data-status"]
  end

  test "#access_token_status_badge should label an inactive token inactive" do
    access_token = create(:access_token, user: user, status: :inactive)

    badge = render_inline_badge(access_token_status_badge(access_token))

    assert_equal "Inactive", badge.text
    assert_equal "inactive", badge["data-status"]
  end

  test "#access_token_status_badge should stay silent while the check is in flight" do
    access_token = create(:access_token, user: user, status: :validating)

    assert_nil access_token_status_badge(access_token)
  end

  test "#credential_status_badge should label a credential by its state" do
    credential = create(:ai_credential, :inactive, user: user)

    badge = render_inline_badge(credential_status_badge(credential))

    assert_equal "Inactive", badge.text
    assert_equal "inactive", badge["data-credential-state"]
    assert_equal "ai_credential.status_badge", badge["data-key"]
  end

  test "#credential_status_badge should stay silent while the check is in flight" do
    credential = create(:search_credential, user: user, state: :validating)

    assert_nil credential_status_badge(credential)
  end

  test "#credential_actions_menu_items should list edit, make default, and delete" do
    credential = create(:ai_credential, user: user)

    labels = credential_actions_menu_items(credential, delete_confirm: "Sure?").map { _1[:label] }

    assert_equal ["Edit", "Make default", nil, "Delete…"], labels
  end

  test "#credential_actions_menu_items should omit make default for the default credential" do
    credential = create(:ai_credential, :default, user: user)

    labels = credential_actions_menu_items(credential, delete_confirm: "Sure?").map { _1[:label] }

    assert_equal ["Edit", nil, "Delete…"], labels
  end

  test "#credential_actions_menu_items should separate delete from the actions above it" do
    credential = create(:ai_credential, user: user)

    items = credential_actions_menu_items(credential, delete_confirm: "Sure?")

    assert items[-2][:separator]
    assert_equal "Delete…", items.last[:label]
  end

  test "#credential_actions_menu_items should wire the actions to their routes" do
    credential = create(:search_credential, user: user)

    items = credential_actions_menu_items(credential, delete_confirm: "Delete this search credential?")
              .reject { _1[:separator] }.index_by { _1[:label] }

    assert_equal edit_search_credential_path(credential), items["Edit"][:href]
    assert_equal search_credential_default_path(credential), items["Make default"][:href]
    assert_equal :patch, items["Make default"][:method]
    assert_equal search_credential_path(credential), items["Delete…"][:href]
    assert_equal :delete, items["Delete…"][:method]
    assert_equal "Delete this search credential?", items["Delete…"].dig(:data, :turbo_confirm)
  end

  test "#credential_actions_menu_items should namespace test hooks by credential type" do
    credential = create(:search_credential, user: user)

    keys = credential_actions_menu_items(credential, delete_confirm: "Sure?").map { _1.dig(:data, :key) }

    assert_equal ["search_credential.edit", "search_credential.make-default", nil, "search_credential.delete"], keys
  end

  test "#access_token_actions_menu_items should list edit and delete around a separator" do
    access_token = create(:access_token, user: user)

    items = access_token_actions_menu_items(access_token)

    assert_equal ["Edit", nil, "Delete…"], items.map { _1[:label] }
    assert items[1][:separator]
    assert_equal edit_access_token_path(access_token), items.first[:href]
  end

  test "#access_token_actions_menu_items should open the delete confirmation modal" do
    access_token = create(:access_token, user: user)

    delete_item = access_token_actions_menu_items(access_token).last

    assert_equal "delete-token-modal", delete_item.dig(:data, :modal_trigger_modal_id_value)
    assert_equal "click->modal-trigger#open", delete_item.dig(:data, :action)
  end

  private

  def render_inline_badge(badge)
    Nokogiri::HTML5.fragment(render(badge)).at_css("span")
  end
end
