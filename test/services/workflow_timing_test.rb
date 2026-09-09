require "test_helper"

class WorkflowTimingTest < ActiveSupport::TestCase
  class FailingWorkflow
    include Workflow

    step :fail_step

    attr_reader :duration_seen_on_error, :total_duration_seen_on_error

    def run
      execute
    end

    private

    def fail_step(*)
      raise "boom"
    end

    def on_error(*)
      @duration_seen_on_error = step_durations.fetch(current_step)
      @total_duration_seen_on_error = total_duration
    end
  end

  test "#execute should finalize timers before on_error" do
    workflow = FailingWorkflow.new

    assert_raises(RuntimeError) { workflow.run }
    assert_kind_of Numeric, workflow.duration_seen_on_error
    assert_operator workflow.total_duration_seen_on_error, :>=, workflow.duration_seen_on_error
  end
end
