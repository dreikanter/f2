require "test_helper"

class CredentialHelperTest < ActionView::TestCase
  def user
    @user ||= create(:user)
  end

  test "#credential_state_badge should use the shared state contract" do
    credentials = [
      create(:access_token, user: user, state: :inactive),
      create(:ai_credential, :inactive, user: user),
      create(:search_credential, :inactive, user: user)
    ]

    credentials.each do |credential|
      badge = render_inline_badge(credential_state_badge(credential))

      assert_equal "Inactive", badge.text
      assert_equal "inactive", badge["data-credential-state"]
      assert_equal "#{credential.model_name.param_key}.state_badge", badge["data-key"]
    end
  end

  test "#credential_state_badge should stay silent while a check is in flight" do
    credentials = [
      create(:access_token, user: user, state: :validating),
      create(:ai_credential, user: user, state: :validating)
    ]

    credentials.each { |credential| assert_nil credential_state_badge(credential) }
  end

  test "#credential_actions_menu_items should include Details only when requested" do
    credential = create(:search_credential, user: user)

    header_labels = credential_actions_menu_items(credential).map { _1[:label] }
    list_labels = credential_actions_menu_items(credential, include_details: true).map { _1[:label] }

    assert_equal ["Edit", "Make default", nil, "Delete…"], header_labels
    assert_equal ["Details", "Edit", "Make default", nil, "Delete…"], list_labels
  end

  test "#credential_actions_menu_items should treat default selection as optional" do
    access_token = create(:access_token, user: user)
    default_credential = create(:ai_credential, :default, user: user)

    assert_equal ["Edit", nil, "Delete…"], credential_actions_menu_items(access_token).map { _1[:label] }
    assert_equal ["Edit", nil, "Delete…"], credential_actions_menu_items(default_credential).map { _1[:label] }
  end

  test "#credential_actions_menu_items should wire shared routes, hooks, and modal deletion" do
    credential = create(:search_credential, user: user)
    items = credential_actions_menu_items(credential, include_details: true)
              .reject { _1[:separator] }.index_by { _1[:label] }

    assert_equal search_credential_path(credential), items["Details"][:href]
    assert_equal edit_search_credential_path(credential), items["Edit"][:href]
    assert_equal search_credential_default_path(credential), items["Make default"][:href]
    assert_equal :patch, items["Make default"][:method]
    assert_equal "#", items["Delete…"][:href]
    assert_equal CredentialDeleteModalComponent.modal_id(credential),
                 items["Delete…"].dig(:data, :modal_trigger_modal_id_value)
    assert_equal ["search_credential.details", "search_credential.edit", "search_credential.make-default",
                  "search_credential.delete"], items.values.map { _1.dig(:data, :key) }
  end

  private

  def render_inline_badge(badge)
    Nokogiri::HTML5.fragment(render(badge)).at_css("span")
  end
end
