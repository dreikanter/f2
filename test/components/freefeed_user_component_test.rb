require "test_helper"
require "view_component/test_case"

class FreefeedUserComponentTest < ViewComponent::TestCase
  test "#render should show the username" do
    result = render_inline(FreefeedUserComponent.new(user: { "username" => "testuser" }))

    assert_includes result.text, "testuser"
  end

  test "#render should show the userpic when the user info has one" do
    user = {
      "username" => "testuser",
      "profile_picture_url" => "https://media.freefeed.net/profilepics/testuser_75.jpg"
    }

    result = render_inline(FreefeedUserComponent.new(user: user))

    img = result.css('[data-key="freefeed_user.userpic"]').first
    assert_equal ImgproxyUrl.userpic(user["profile_picture_url"]), img["src"]
    assert_equal "testuser", img["alt"]
  end

  test "#render should fall back to the placeholder userpic" do
    result = render_inline(FreefeedUserComponent.new(user: { "username" => "testuser" }))

    img = result.css('[data-key="freefeed_user.userpic"]').first
    assert_includes img["src"], "default-userpic-75"
  end
end
