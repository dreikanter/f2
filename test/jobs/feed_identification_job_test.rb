require "test_helper"

class FeedIdentificationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  test "#perform should handle a missing identification gracefully" do
    assert_nothing_raised { FeedIdentificationJob.perform_now(SecureRandom.uuid, SecureRandom.uuid) }
  end

  test "#perform should not write after timeout rotates run_id" do
    url = "http://example.com/feed.xml"
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, user: user, input: url, status: :processing,
                                                   started_at: Time.current, run_id: run_id)
    stub_request(:get, url)

    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)
    FeedIdentificationJob.perform_now(identification.id, run_id)

    assert_not_requested :get, url
    assert_predicate identification.reload, :timed_out?
  end

  test "#perform should not recreate a cancelled identification" do
    url = "http://example.com/feed.xml"
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, user: user, input: url, status: :processing,
                                                   started_at: Time.current, run_id: run_id)
    identification.destroy!
    stub_request(:get, url)

    FeedIdentificationJob.perform_now(identification.id, run_id)

    assert_not_requested :get, url
    assert_not FeedIdentification.exists?(identification.id)
    assert_nil FeedIdentification.find_by(user: user, input: url)
  end

  test "#perform should ignore a superseded run" do
    url = "http://example.com/feed.xml"
    identification = create(:feed_identification, user: user, input: url, status: :processing,
                                                   started_at: Time.current, run_id: SecureRandom.uuid)
    original_attributes = identification.attributes.slice("status", "run_id", "started_at", "updated_at")
    stub_request(:get, url)

    FeedIdentificationJob.perform_now(identification.id, SecureRandom.uuid)

    assert_not_requested :get, url
    assert_equal original_attributes,
                 identification.reload.attributes.slice("status", "run_id", "started_at", "updated_at")
  end
end
