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

  test "#settle! should run a terminal write once" do
    token = create(:access_token, state: :validating)
    run = create(:operation_run, subject: token)

    assert run.succeed! { |subject| subject.update!(state: :active) }
    assert_not run.fail! { flunk "a settled run must ignore late work" }

    assert_predicate run.reload, :succeeded?
    assert_predicate token.reload, :active?
    assert_not_nil run.finished_at
  end

  test "#in_progress? should support a stale-job fallback" do
    run = create(:operation_run, started_at: 16.minutes.ago)

    assert run.in_progress?
    assert_not run.in_progress?(stale_after: 15.minutes)
  end
end
