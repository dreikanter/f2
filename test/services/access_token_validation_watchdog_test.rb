require "test_helper"

class AccessTokenValidationWatchdogTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def abandoned_token
    @abandoned_token ||= create(
      :access_token,
      user: user,
      status: :validating,
      validation_started_at: (AccessToken::VALIDATION_STALE_AFTER + 1.minute).ago
    )
  end

  test "#call should settle a validation whose run never reported back" do
    assert AccessTokenValidationWatchdog.new(abandoned_token).call

    assert abandoned_token.reload.inactive?
    assert_nil abandoned_token.validation_started_at
  end

  test "#call should leave a validation that is still in flight alone" do
    token = create(:access_token, user: user, status: :validating, validation_started_at: 1.minute.ago)

    assert_not AccessTokenValidationWatchdog.new(token).call
    assert token.reload.validating?
  end

  test "#call should settle a run abandoned after its retries were exhausted" do
    token = create(
      :access_token,
      user: user,
      status: :pending,
      validation_started_at: (AccessToken::VALIDATION_STALE_AFTER + 1.minute).ago
    )

    assert AccessTokenValidationWatchdog.new(token).call
    assert token.reload.inactive?
  end

  test "#call should leave a token that never opened a validation alone" do
    token = create(:access_token, user: user, status: :pending, validation_started_at: nil)

    assert_not AccessTokenValidationWatchdog.new(token).call
    assert token.reload.pending?
  end

  test "#call should leave a settled token alone" do
    token = create(
      :access_token,
      :active,
      user: user,
      validation_started_at: (AccessToken::VALIDATION_STALE_AFTER + 1.minute).ago
    )

    assert_not AccessTokenValidationWatchdog.new(token).call
    assert token.reload.active?
  end

  test "#call should take the token's feeds down and say why" do
    # A feed only enables behind an active token, so it predates the run.
    abandoned_token.update!(status: :active)
    feed = create(:feed, user: user, access_token: abandoned_token, state: :enabled)
    abandoned_token.update!(status: :validating)

    AccessTokenValidationWatchdog.new(abandoned_token).call

    assert_equal "disabled", feed.reload.state
    event = Event.find_by!(subject: abandoned_token)
    assert_equal AccessTokenValidationWatchdog::EVENT_TYPE, event.type
    assert_equal [feed.id], event.metadata["disabled_feed_ids"]
  end
end
