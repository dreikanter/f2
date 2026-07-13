require "test_helper"
require "view_component/test_case"

class SearchCredentialsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, :active, user: user)
  end

  test "#call should render each credential as a list item" do
    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='search_credential.#{credential.id}']").first
  end

  test "#call should link to the credential show page" do
    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))
    link = result.css("a").first

    assert_not_nil link
    assert_includes link["href"], "/search_credentials/#{credential.id}"
  end

  test "#call should show the provider display name" do
    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))

    assert_includes result.text, "Serper"
  end

  test "#call should show default badge for the default credential" do
    user.update!(default_search_credential: credential)

    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='search_credential.default-badge']").first
  end

  test "#call should not show default badge for a non-default credential" do
    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))

    assert_empty result.css("[data-key='search_credential.default-badge']")
  end

  test "#call should show inactive status icon for inactive credentials" do
    inactive = create(:search_credential, :inactive, user: user)

    result = render_inline(SearchCredentialsListComponent.new(credentials: [inactive]))

    icon = result.at_css("[data-key='search_credential.#{inactive.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Inactive", icon["aria-label"]
  end

  test "#call should render management menu items" do
    result = render_inline(SearchCredentialsListComponent.new(credentials: [credential]))
    items = result.css("a[role='menuitem']").to_h { |item| [item.text.strip, item] }

    assert_includes items.fetch("Details")["href"], "/search_credentials/#{credential.id}"
    assert_includes items.fetch("Edit")["href"], "/search_credentials/#{credential.id}/edit"
    assert_not_nil items["Make default"]
    assert_not_nil items["Delete…"]
  end
end
