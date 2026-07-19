require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "should generate a token on create" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_match WebhookEndpoint::TOKEN_PATTERN, endpoint.encrypted_token
  end

  test "should keep an explicitly assigned token" do
    token = WebhookEndpoint.generate_token
    endpoint = create(:webhook_endpoint, feed: feed, encrypted_token: token)

    assert_equal token, endpoint.encrypted_token
  end

  test "should require a unique token" do
    token = WebhookEndpoint.generate_token
    create(:webhook_endpoint, feed: feed, encrypted_token: token)
    duplicate = build(:webhook_endpoint, feed: create(:feed), encrypted_token: token)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:encrypted_token, :taken)
  end

  test "should allow only one endpoint per feed" do
    create(:webhook_endpoint, feed: feed)
    duplicate = build(:webhook_endpoint, feed: feed)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:feed_id, :taken)
  end

  test "should persist the token encrypted at rest" do
    endpoint = create(:webhook_endpoint, feed: feed)
    connection = WebhookEndpoint.connection
    stored_value = connection.select_value(
      "SELECT encrypted_token FROM webhook_endpoints WHERE id = #{connection.quote(endpoint.id)}"
    )

    assert_not_equal endpoint.encrypted_token, stored_value
    assert_not_includes stored_value, endpoint.encrypted_token
  end

  test ".authenticate should resolve an endpoint from its token" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_equal endpoint, WebhookEndpoint.authenticate(endpoint.encrypted_token)
  end

  test ".authenticate should reject malformed tokens without querying" do
    queried = false

    WebhookEndpoint.stub(:find_by, ->(*) { queried = true }) do
      assert_nil WebhookEndpoint.authenticate("too-short")
    end

    assert_not queried
  end

  test "#rate_limit_subject should use the stable endpoint id" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_equal "webhook_endpoint:#{endpoint.id}", endpoint.rate_limit_subject
  end

  test "#rotate! should replace the token so the old one stops authenticating" do
    endpoint = create(:webhook_endpoint, feed: feed)
    old_token = endpoint.encrypted_token

    endpoint.rotate!

    assert_not_equal old_token, endpoint.reload.encrypted_token
    assert_nil WebhookEndpoint.authenticate(old_token)
  end

  test "should remove rate-limit state when destroyed" do
    endpoint = create(:webhook_endpoint, feed: feed)
    key = "webhook_ingest:#{endpoint.rate_limit_subject}"
    RateLimit.acquire(:webhook_ingest, subject: endpoint.rate_limit_subject, cost: { request: 1 })
    assert RateLimit::Bucket.exists?(key: key)

    endpoint.destroy!

    assert_not RateLimit::Bucket.exists?(key: key)
  end

  test "should default received_count to zero" do
    endpoint = create(:webhook_endpoint, feed: feed)

    assert_equal 0, endpoint.received_count
    assert_nil endpoint.last_received_at
  end
end
