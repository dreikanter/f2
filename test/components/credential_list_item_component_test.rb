require "test_helper"
require "view_component/test_case"

class CredentialListItemComponentTest < ViewComponent::TestCase
  CASES = {
    access_token: { trait: :active, path_segment: "access_tokens" },
    ai_credential: { trait: :active, path_segment: "ai_credentials" },
    search_credential: { trait: :active, path_segment: "search_credentials" }
  }.freeze

  def user
    @user ||= create(:user)
  end

  def each_case(trait: nil)
    CASES.each do |factory, expected|
      credential = create(factory, trait || expected[:trait], user: user)
      result = render_inline(CredentialListItemComponent.new(credential: credential))
      yield result, credential, expected
    end
  end

  def menu_item(result, label)
    result.css("[role='menuitem']").find { |item| item.text.strip == label }
  end

  test "#render should use shared row and state-icon hooks" do
    each_case do |result, credential, _expected|
      key = credential.model_name.param_key

      assert_not_nil result.at_css("[data-key='#{key}.#{credential.id}']"), key
      assert_not_nil result.at_css("[data-key='#{key}.#{credential.id}.state_icon'] svg"), key
    end
  end

  test "#render should link the display name to the credential" do
    each_case do |result, credential, expected|
      link = result.css("a").first

      assert_includes link["href"], "/#{expected[:path_segment]}/#{credential.id}"
      assert_equal credential.display_name, link.text.strip
    end
  end

  test "#render should show the provider name" do
    each_case do |result, credential, _expected|
      assert_includes result.text, credential.provider_name
    end
  end

  test "#render should offer Details, Edit, and modal-backed Delete actions" do
    each_case do |result, credential, expected|
      assert_includes menu_item(result, "Details")["href"], "/#{expected[:path_segment]}/#{credential.id}"
      assert_includes menu_item(result, "Edit")["href"], "/#{expected[:path_segment]}/#{credential.id}/edit"

      delete = menu_item(result, "Delete…")
      assert_equal CredentialDeleteModalComponent.modal_id(credential), delete["data-modal-trigger-modal-id-value"]
      assert_equal "modal-trigger", delete["data-controller"]
    end
  end

  test "#render should separate Delete from the actions above it" do
    each_case do |result, credential, _expected|
      menu = result.at_css("##{credential.model_name.param_key.dasherize}-menu-#{credential.id}")

      assert_equal "separator", menu.css("li")[-2]["role"]
      assert_equal "Delete…", menu.css("li").last.text.strip
    end
  end

  test "#render should offer Make default only for defaultable credentials" do
    each_case do |result, credential, _expected|
      if credential.respond_to?(:default?)
        assert_not_nil menu_item(result, "Make default")
      else
        assert_nil menu_item(result, "Make default")
      end
    end
  end

  test "#render should badge a default credential and omit Make default" do
    credential = create(:ai_credential, :active, user: user)
    user.update!(default_ai_credential: credential)
    result = render_inline(CredentialListItemComponent.new(credential: credential))

    assert_not_nil result.at_css("[data-key='ai_credential.default-badge']")
    assert_nil menu_item(result, "Make default")
  end
end
