require "test_helper"

class OperationRunTest < ActiveSupport::TestCase
  test "kind and status should use integer enums" do
    assert_equal :integer, OperationRun.type_for_attribute("kind").type
    assert_equal :integer, OperationRun.type_for_attribute("status").type
  end

  test ".start! should supersede the current run for the same subject and kind" do
    token = create(:access_token)
    old_run = create(:operation_run, subject: token)

    run = OperationRun.start!(subject: token, kind: :validation, timeout: 5.minutes)

    assert_predicate old_run.reload, :superseded?
    assert_predicate run, :running?
    assert_equal run.started_at + 5.minutes, run.deadline_at
  end

  test ".start! should not supersede a different operation kind" do
    detail = create(:access_token_detail)
    refresh = create(:operation_run, subject: detail, kind: :groups_refresh)

    OperationRun.start!(subject: detail, kind: :validation)

    assert_predicate refresh.reload, :running?
  end

  test "#claim! should start a queued run once" do
    run = create(:operation_run, status: :queued, started_at: nil, deadline_at: nil)
    yielded_deadline = nil

    freeze_time do
      assert run.claim!(timeout: 5.minutes) { |_subject, deadline| yielded_deadline = deadline }
      assert_equal Time.current, run.started_at
      assert_equal 5.minutes.from_now, yielded_deadline
    end

    assert_predicate run, :running?
    assert run.claim!(timeout: 5.minutes) { flunk "an already-running run should not be started twice" }
  end

  test "#succeed! should apply the result and reject later transitions" do
    token = create(:access_token, state: :validating)
    run = create(:operation_run, subject: token)

    assert run.succeed! { |subject| subject.update!(state: :active) }
    assert_not run.fail! { flunk "a settled run must ignore late work" }

    assert_predicate run.reload, :succeeded?
    assert_predicate token.reload, :active?
    assert_not_nil run.finished_at
  end

  test "#in_progress? should use the recorded deadline regardless of age" do
    freeze_time do
      run = build(:operation_run, started_at: 1.hour.ago, deadline_at: 1.minute.from_now)

      assert_predicate run, :in_progress?

      travel_to run.deadline_at

      assert_not_predicate run, :in_progress?
    end
  end

  test "#in_progress? should keep queued runs without a deadline in progress" do
    run = build(:operation_run, status: :queued, created_at: 1.day.ago, started_at: nil, deadline_at: nil)

    assert_predicate run, :in_progress?
  end

  test "#in_progress? should exclude terminal runs before their deadline" do
    run = build(:operation_run, deadline_at: 1.minute.from_now)

    %i[succeeded failed timed_out superseded].each do |status|
      run.status = status

      assert_not_predicate run, :in_progress?, status.to_s
    end
  end

  test "#unsuccessful? should cover both unsuccessful terminal statuses" do
    run = create(:operation_run)

    OperationRun.statuses.each_key do |status|
      run.update!(status: status)

      assert_equal status.in?(%w[failed timed_out]), run.unsuccessful?, status
    end
  end
end
