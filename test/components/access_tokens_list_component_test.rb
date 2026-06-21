require "test_helper"
require "view_component/test_case"

class AccessTokensListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user, name: "My Token")
  end

  test "#call should render each token as a list item" do
    result = render_inline(AccessTokensListComponent.new(access_tokens: [access_token]))

    assert_not_nil result.css("[data-key='settings.access_tokens.#{access_token.id}']").first
  end

  test "#call should link to the token show page" do
    result = render_inline(AccessTokensListComponent.new(access_tokens: [access_token]))
    link = result.css("a[href*='/access_tokens/#{access_token.id}']").first

    assert_not_nil link
  end

  test "#call should show owner and host in metadata when owner is present" do
    result = render_inline(AccessTokensListComponent.new(access_tokens: [access_token]))

    assert_includes result.text, "@#{access_token.owner} at #{access_token.host_domain}"
  end

  test "#call should fall back to host domain when owner is blank" do
    token = create(:access_token, user: user, owner: nil)
    result = render_inline(AccessTokensListComponent.new(access_tokens: [token]))

    assert_includes result.text, token.host_domain
  end

  test "#call should show 'Never used' for tokens that were never used" do
    result = render_inline(AccessTokensListComponent.new(access_tokens: [access_token]))

    assert_includes result.text, "Never used"
  end

  test "#call should render nothing for an empty collection" do
    result = render_inline(AccessTokensListComponent.new(access_tokens: []))

    assert_empty result.css("div")
  end
end
