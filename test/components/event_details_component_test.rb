require "test_helper"
require "view_component/test_case"

class EventDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test "#call should render the created timestamp without admin extras" do
    event = create(:event, type: "owned_event", level: :warning, subject: feed)

    result = render_inline(EventDetailsComponent.new(event: event))

    assert_includes result.to_html, "Created"
    assert_empty result.css('[data-key="admin.event.user"]')
  end

  test "#call should render a compact user link when admin" do
    event = create(:event, type: "owned_event", user: user, subject: feed)

    result = render_inline(EventDetailsComponent.new(event: event, admin: true))
    link = result.css("a[data-key='admin.event.user']").first

    assert_equal event.user_id.to_s.last(5), link.text
    assert_equal "/admin/users/#{event.user_id}", link["href"]
    assert_equal "#{event.user_id} — #{user.email_address}", link["title"]
  end

  test "#call should merge metadata stats into the details list" do
    event = create(:event, type: "owned_event", subject: feed,
                   metadata: { "stats" => { "new_posts" => 1234, "llm_cost_cents" => 250 } })

    result = render_inline(EventDetailsComponent.new(event: event))

    assert_equal "New posts", result.css('[data-key="events.stats.new_posts.label"]').text
    assert_equal "1,234", result.css('[data-key="events.stats.new_posts.value"]').text
    assert_equal "Estimated AI spend", result.css('[data-key="events.stats.llm_cost_cents.label"]').text
    assert_equal "$2.50", result.css('[data-key="events.stats.llm_cost_cents.value"]').text
  end

  test "#call should not render a search calls stat row" do
    event = create(:event, type: "owned_event", subject: feed,
                   metadata: { "stats" => { "search_calls" => 2 } })

    result = render_inline(EventDetailsComponent.new(event: event))

    assert_empty result.css('[data-key="events.stats.search_calls"]')
  end
end
