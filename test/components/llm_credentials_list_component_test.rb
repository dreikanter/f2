require "test_helper"
require "view_component/test_case"

class LlmCredentialsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, :active, user: user)
  end

  test "#call should render each credential as a list item" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='llm_credential.#{credential.id}']").first
  end

  test "#call should link to the credential show page" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))
    link = result.css("a").first

    assert_not_nil link
    assert_includes link["href"], "/llm_credentials/#{credential.id}"
  end

  test "#call should show default badge for the default credential" do
    credential.make_default!
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))

    assert_not_nil result.css("[data-key='llm_credential.default-badge']").first
  end

  test "#call should not show default badge for non-default credentials" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))

    assert_empty result.css("[data-key='llm_credential.default-badge']")
  end

  test "#call should show inactive note for inactive credentials" do
    inactive = create(:llm_credential, :inactive, user: user)
    result = render_inline(LlmCredentialsListComponent.new(credentials: [inactive]))

    assert_includes result.text, "This key didn't work"
  end

  test "#call should not show inactive note for active credentials" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))

    assert_not_includes result.text, "This key didn't work"
  end

  test "#call should show capitalized status" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))

    assert_includes result.text, "Status: Active"
  end

  test "#call should render a Details menu item linking to the show page" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Details" }

    assert_not_nil item
    assert_includes item["href"], "/llm_credentials/#{credential.id}"
  end

  test "#call should render an Edit menu item linking to the edit page" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Edit" }

    assert_not_nil item
    assert_includes item["href"], "/llm_credentials/#{credential.id}/edit"
  end

  test "#call should render the Delete menu item with default text color" do
    result = render_inline(LlmCredentialsListComponent.new(credentials: [credential]))
    item = result.css("a[role='menuitem']").find { |a| a.text.strip == "Delete" }

    assert_not_nil item
    assert_includes item["class"], "text-slate-700"
    assert_not_includes item["class"], "text-red-600"
  end
end
