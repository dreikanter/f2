require "test_helper"

class PolledRunTest < ActiveSupport::TestCase
  test ".polling_max_polls should preserve the polling interval and timeout budget" do
    assert_equal 2500, PolledRun::POLLING_INTERVAL_MS
    assert_equal 85.seconds, PolledRun::TIMEOUT_AFTER
    assert_equal 36, FeedIdentification.polling_max_polls

    final_poll_at = (FeedIdentification.polling_max_polls - 1) * PolledRun::POLLING_INTERVAL_MS
    assert_equal PolledRun::POLLING_INTERVAL_MS, final_poll_at - PolledRun::TIMEOUT_AFTER.in_milliseconds
  end

  test ".polls_within should budget a longer deadline the same way" do
    assert_equal 98, FeedPreview.polls_within(4.minutes)
  end

  test "#settle_timeout! should ignore a run token that no longer matches" do
    identification = create(:feed_identification, status: :processing, run_id: SecureRandom.uuid)

    identification.settle_timeout!(run_id: SecureRandom.uuid, status: :timed_out, from: :processing)

    assert_predicate identification.reload, :processing?
  end

  test "#settle_timeout! should rotate the run token once it settles" do
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, status: :processing, run_id: run_id)

    identification.settle_timeout!(run_id: run_id, status: :timed_out, from: :processing)

    assert_predicate identification, :timed_out?
    assert_not_equal run_id, identification.run_id
  end
end
