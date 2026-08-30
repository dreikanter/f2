require "test_helper"

class AccessTokenValidationTimeoutJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  test "#perform should settle the matching run without disabling feeds" do
    run_id = SecureRandom.uuid
    token = create(:access_token, user: user, status: :active)
    feed = create(:feed, user: user, access_token: token, state: :enabled)
    token.update!(status: :validating, validation_started_at: 15.minutes.ago, validation_run_id: run_id)

    assert_difference -> { Event.where(type: AccessToken::VALIDATION_ABANDONED_EVENT_TYPE).count }, 1 do
      AccessTokenValidationTimeoutJob.perform_now(token.id, run_id)
    end

    assert token.reload.inactive?
    assert_nil token.validation_started_at
    assert_nil token.validation_run_id
    assert feed.reload.enabled?
  end

  test "#perform should ignore a superseded run" do
    current_run_id = SecureRandom.uuid
    token = create(:access_token, user: user, status: :validating,
                                  validation_started_at: Time.current, validation_run_id: current_run_id)
    original_attributes = token.attributes.slice(
      "status", "validation_started_at", "validation_run_id", "updated_at"
    )

    assert_no_difference("Event.count") do
      AccessTokenValidationTimeoutJob.perform_now(token.id, SecureRandom.uuid)
    end

    assert_equal original_attributes, token.reload.attributes.slice(*original_attributes.keys)
  end

  test "#perform should ignore a missing token" do
    assert_nothing_raised do
      AccessTokenValidationTimeoutJob.perform_now(SecureRandom.uuid, SecureRandom.uuid)
    end
  end
end
