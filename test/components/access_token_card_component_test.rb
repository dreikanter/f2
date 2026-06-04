require "test_helper"
require "view_component/test_case"

class AccessTokenCardComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  test "#call should render the token name as a link to the show page" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))
    link = result.css("a[href*='/access_tokens/#{access_token.id}']").first

    assert_not_nil link
    assert_equal access_token.name, link.text.strip
  end

  test "#call should render the Edit menu item linking to the edit page" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))
    edit_link = result.css("a[href*='/access_tokens/#{access_token.id}/edit']").first

    assert_not_nil edit_link
    assert_equal "Edit", edit_link.text.strip
  end

  test "#call should render the Delete menu item with modal trigger" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))
    delete_link = result.css("a[data-controller='modal-trigger']").first

    assert_not_nil delete_link
    assert_equal "Delete", delete_link.text.strip
    assert_equal "delete-token-modal-#{access_token.id}", delete_link["data-modal-trigger-modal-id-value"]
  end

  test "#call should display owner and host domain" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))

    assert_includes result.text, "#{access_token.owner}@#{access_token.host_domain}"
  end

  test "#call should display host domain when owner is blank" do
    token = create(:access_token, user: user, owner: nil)
    result = render_inline(AccessTokenCardComponent.new(access_token: token))

    assert_includes result.text, token.host_domain
    assert_not_includes result.text, "@"
  end

  test "#call should show 'Never used' when last_used_at is nil" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))

    assert_includes result.text, "Never used"
  end

  test "#call should show last used time when available" do
    token = create(:access_token, :active, :recently_used, user: user)
    result = render_inline(AccessTokenCardComponent.new(access_token: token))

    assert_includes result.text, "Used"
    assert_not_includes result.text, "Never used"
  end

  test "#call should display the token status" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))

    assert_includes result.text, "Active"
  end

  test "#call should set data-key attribute" do
    result = render_inline(AccessTokenCardComponent.new(access_token: access_token))

    assert_not_nil result.css("[data-key='settings.access_tokens.#{access_token.id}']").first
  end
end
