require "test_helper"
require "view_component/test_case"

class ListGroupComponent::AccessTokenItemComponentTest < ViewComponent::TestCase
  def access_token
    @access_token ||= create(:access_token, :active, owner: "testuser", name: "Test Token")
  end

  test "#render should display access token information" do
    component = ListGroupComponent::AccessTokenItemComponent.new(
      access_token: access_token,
      key: "settings.access_tokens.#{access_token.id}"
    )

    result = render_inline(component)
    item = result.css("[data-key='settings.access_tokens.#{access_token.id}']").first

    assert_not_nil item
  end

  test "#render should display 'Never' for last_used_at when nil" do
    access_token = create(:access_token, :active, last_used_at: nil)
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)

    assert_includes result.text, "Used: Never"
  end

  test "#render should display last used time when present" do
    access_token = create(:access_token, :active, last_used_at: 1.hour.ago)
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)

    assert_includes result.text, "Used: 1h"
  end

  test "#render should display active status icon" do
    access_token = create(:access_token, :active)
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)
    icon = result.css("i.bi-check-circle").first

    assert_not_nil icon
  end

  test "#render should display inactive status icon" do
    access_token = create(:access_token, :inactive)
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)
    icon = result.css("i.bi-x-circle").first

    assert_not_nil icon
  end

  test "#render should display pending status icon" do
    access_token = create(:access_token)
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)
    icon = result.css("i.bi-clock").first

    assert_not_nil icon
  end

  test "#render should link to access token show page" do
    component = ListGroupComponent::AccessTokenItemComponent.new(access_token: access_token)
    result = render_inline(component)
    link = result.css("a").first

    assert_not_nil link
    assert_includes link.attributes["href"].value, "/settings/access_tokens/#{access_token.id}"
  end
end
