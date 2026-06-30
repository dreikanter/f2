require "test_helper"
require "view_component/test_case"

class AiCredentialsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user)
  end

  test "#call should render each credential as a list item" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='ai_credential.#{credential.id}']").first
  end

  test "#call should link to the credential show page" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))
    link = result.css("a").first

    assert_not_nil link
    assert_includes link["href"], "/ai_credentials/#{credential.id}"
  end

  test "#call should show default badge for the default credential" do
    user.update!(default_ai_credential: credential)
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='ai_credential.default-badge']").first
  end

  test "#call should not show default badge for non-default credentials" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))

    assert_empty result.css("[data-key='ai_credential.default-badge']")
  end

  test "#call should show inactive status icon for inactive credentials" do
    inactive = create(:ai_credential, :inactive, user: user)
    result = render_inline(AiCredentialsListComponent.new(credentials: [inactive]))

    icon = result.at_css("[data-key='ai_credential.#{inactive.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Inactive", icon["aria-label"]
  end

  test "#call should show active status icon for active credentials" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))

    icon = result.at_css("[data-key='ai_credential.#{credential.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Active", icon["aria-label"]
  end

  test "#call should render a Details menu item linking to the show page" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Details" }

    assert_not_nil item
    assert_includes item["href"], "/ai_credentials/#{credential.id}"
  end

  test "#call should render an Edit menu item linking to the edit page" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Edit" }

    assert_not_nil item
    assert_includes item["href"], "/ai_credentials/#{credential.id}/edit"
  end

  test "#call should render the Delete menu item with default text color" do
    result = render_inline(AiCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Delete…" }

    assert_not_nil item
    assert_includes item["class"], "text-heading"
    assert_not_includes item["class"], "text-danger"
  end
end
