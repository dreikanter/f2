require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "should generate a token on create" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_operator endpoint.encrypted_token.length, :>=, 43
  end

  test "should keep an explicitly assigned token" do
    endpoint = create(:webhook_endpoint, feed: feed, encrypted_token: "explicit-token")

    assert_equal "explicit-token", endpoint.encrypted_token
  end

  test "should require a unique token" do
    create(:webhook_endpoint, feed: feed, encrypted_token: "taken")
    duplicate = build(:webhook_endpoint, feed: create(:feed), encrypted_token: "taken")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:encrypted_token, :taken)
  end

  test "should allow only one endpoint per feed" do
    create(:webhook_endpoint, feed: feed)
    duplicate = build(:webhook_endpoint, feed: feed)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:feed_id, :taken)
  end

  test "should be findable by token through deterministic encryption" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_equal endpoint, WebhookEndpoint.find_by(encrypted_token: endpoint.encrypted_token)
  end

  test "#rotate! should replace the token so the old one stops resolving" do
    endpoint = create(:webhook_endpoint, feed: feed)
    old_token = endpoint.encrypted_token

    endpoint.rotate!

    assert_not_equal old_token, endpoint.reload.encrypted_token
    assert_nil WebhookEndpoint.find_by(encrypted_token: old_token)
  end

  test "should default received_count to zero" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_equal 0, endpoint.received_count
    assert_nil endpoint.last_received_at
  end
end
