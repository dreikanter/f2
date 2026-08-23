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

  test "#call should leave the token's feeds running" do
    # A delayed job may still land and find the token fine; feeds taken down
    # here would stay down after it did.
    abandoned_token.update!(status: :active)
    feed = create(:feed, user: user, access_token: abandoned_token, state: :enabled)
    abandoned_token.update!(status: :validating)

    AccessTokenValidationWatchdog.new(abandoned_token).call

    assert_equal "enabled", feed.reload.state
  end

  test "#call should record why the token went quiet" do
    AccessTokenValidationWatchdog.new(abandoned_token).call

    event = Event.find_by!(subject: abandoned_token)
    assert_equal AccessTokenValidationWatchdog::EVENT_TYPE, event.type
    assert_equal "warning", event.level
    assert_equal user, event.user
  end

  test "#call should record the event for a token with no feeds to speak for it" do
    assert_difference -> { Event.where(type: AccessTokenValidationWatchdog::EVENT_TYPE).count }, 1 do
      AccessTokenValidationWatchdog.new(abandoned_token).call
    end
  end

  test "#call should let a delayed run take the token back" do
    AccessTokenValidationWatchdog.new(abandoned_token).call
    assert abandoned_token.reload.inactive?

    # What the job's own run does when it finally reaches the service.
    abandoned_token.update!(status: :active)

    assert abandoned_token.reload.active?
  end
end
