require "test_helper"

class AccessTokenValidationTimeoutJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  test "#perform should settle the run without disabling feeds" do
    token = create(:access_token, user: user, state: :active)
    feed = create(:feed, user: user, access_token: token, state: :enabled)
    token.update!(state: :validating)
    run = create(:operation_run, subject: token, started_at: 15.minutes.ago)

    assert_difference -> { Event.where(type: AccessToken::VALIDATION_ABANDONED_EVENT_TYPE).count }, 1 do
      AccessTokenValidationTimeoutJob.perform_now(run)
    end

    assert_predicate token.reload, :inactive?
    assert_predicate run.reload, :timed_out?
    assert_predicate feed.reload, :enabled?
  end

  test "#perform should ignore a superseded run" do
    token = create(:access_token, user: user, state: :validating)
    stale_run = create(:operation_run, subject: token, status: :superseded, finished_at: Time.current)
    original_attributes = token.attributes.slice("state", "updated_at")

    assert_no_difference("Event.count") do
      AccessTokenValidationTimeoutJob.perform_now(stale_run)
    end

    assert_equal original_attributes, token.reload.attributes.slice(*original_attributes.keys)
  end
end
