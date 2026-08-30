require "test_helper"
require "view_component/test_case"

# Drives both concrete rows, so a subclass that stops inheriting — or a derived
# route, DOM id, or test hook that drifts — fails here rather than silently
# rendering a different row for one credential type.
class CredentialListItemComponentTest < ViewComponent::TestCase
  CASES = {
    AiCredentialListItemComponent => {
      factory: :ai_credential,
      key_prefix: "ai_credential",
      path_segment: "ai_credentials",
      menu_id: "ai-credential-menu",
      noun: "AI credential"
    },
    SearchCredentialListItemComponent => {
      factory: :search_credential,
      key_prefix: "search_credential",
      path_segment: "search_credentials",
      menu_id: "search-credential-menu",
      noun: "search credential"
    }
  }.freeze

  def user
    @user ||= create(:user)
  end

  def each_case(trait = :active)
    CASES.each do |component_class, expected|
      credential = create(expected[:factory], trait, user: user)
      yield render_inline(component_class.new(credential: credential)), credential, expected
    end
  end

  def menu_item(result, label)
    result.css("a[role='menuitem']").find { |a| a.text.strip == label }
  end

  test "#render should namespace the row and status icon hooks per credential type" do
    each_case do |result, credential, expected|
      prefix = expected[:key_prefix]

      assert_not_nil result.css("[data-key='#{prefix}.#{credential.id}']").first, prefix
      assert_not_nil result.at_css("[data-key='#{prefix}.#{credential.id}.status_icon'] svg"), prefix
    end
  end

  test "#render should link the title to the credential" do
    each_case do |result, credential, expected|
      link = result.css("a").first

      assert_includes link["href"], "/#{expected[:path_segment]}/#{credential.id}"
      assert_equal credential.display_name, link.text.strip
    end
  end

  test "#render should show the provider name on the second line" do
    each_case do |result, credential, expected|
      assert_includes result.to_html, provider_name_for(credential), expected[:key_prefix]
    end
  end

  test "#render should offer Details, Edit, Make default and Delete" do
    each_case do |result, credential, expected|
      assert_includes menu_item(result, "Details")["href"], "/#{expected[:path_segment]}/#{credential.id}"
      assert_includes menu_item(result, "Edit")["href"], "/#{expected[:path_segment]}/#{credential.id}/edit"
      assert_includes menu_item(result, "Make default")["href"],
                      "/#{expected[:path_segment]}/#{credential.id}/default"
      assert_not_nil menu_item(result, "Delete…")
    end
  end

  test "#render should name the credential type in the delete prompt" do
    each_case do |result, _credential, expected|
      assert_equal "Delete this #{expected[:noun]}? Feeds using it will be disabled.",
                   menu_item(result, "Delete…")["data-turbo-confirm"]
    end
  end

  test "#render should separate Delete from the actions above it" do
    each_case do |result, credential, expected|
      menu = result.at_css("##{expected[:menu_id]}-#{credential.id}")

      assert_equal "separator", menu.css("li")[-2]["role"], expected[:key_prefix]
      assert_equal "Delete…", menu.css("li").last.text.strip, expected[:key_prefix]
    end
  end

  test "#render should derive the menu id from the credential type" do
    each_case do |result, credential, expected|
      assert_not_nil result.css("##{expected[:menu_id]}-#{credential.id}").first, expected[:menu_id]
    end
  end

  test "#render should badge the default credential and drop its Make default action" do
    ai = create(:ai_credential, :active, user: user)
    user.update!(default_ai_credential: ai)
    result = render_inline(AiCredentialListItemComponent.new(credential: ai))

    assert_not_nil result.css("[data-key='ai_credential.default-badge']").first
    assert_nil menu_item(result, "Make default")
  end

  test "#render should omit the badge for a non-default credential" do
    each_case do |result, _credential, expected|
      assert_empty result.css("[data-key='#{expected[:key_prefix]}.default-badge']")
    end
  end

  private

  def provider_name_for(credential)
    credential.is_a?(AiCredential) ? credential.llm_provider.display_name : credential.provider_label
  end
end
