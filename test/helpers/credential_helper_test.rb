require "test_helper"

class CredentialHelperTest < ActionView::TestCase
  def user
    @user ||= create(:user)
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
end
