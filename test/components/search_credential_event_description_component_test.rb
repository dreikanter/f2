require "test_helper"
require "view_component/test_case"

class SearchCredentialEventDescriptionComponentTest < ViewComponent::TestCase
  test "should render safe linked copy for credential deactivation" do
    credential = create(:search_credential, :active, display_name: "Personal Serper")
    event = Event.create!(
      type: "search_credential_deactivated",
      level: :warning,
      subject: credential,
      user: credential.user
    )

    result = render_inline(EventDescriptionComponent.for(event))

    assert_includes result.to_html, "Search credential"
    assert_includes result.to_html, "Personal Serper"
    assert_includes result.to_html, "/search_credentials/#{credential.id}"
    assert_includes result.to_html, "stopped working"
  end

  test "should render safe linked copy for a web search event" do
    credential = create(:search_credential, :active, display_name: "Personal Serper")
    event = WebSearchUsage.record!(credential: credential)

    result = render_inline(EventDescriptionComponent.for(event))

    assert_includes result.to_html, "Personal Serper"
    assert_includes result.to_html, "/search_credentials/#{credential.id}"
    assert_includes result.to_html, "made a web search request"
    assert_not_includes result.to_html, WebSearchUsage::EVENT_TYPE.humanize
  end
end
