require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  class TestWorkflow
    include Workflow

    step :step_one
    step :step_two
    step :step_three

    attr_reader :execution_log, :step_timings

    def initialize
      @execution_log = []
      @step_timings = {}
    end

    def run_simple_workflow
      execute
    end

    private

    def step_one(input)
      @execution_log << "step_one with #{input.inspect}"
      { value: 2, step: :one }
    end

    def step_two(input)
      @execution_log << "step_two with #{input}"
      { value: input[:value] + 1, step: :two }
    end

    def step_three(input)
      @execution_log << "step_three with #{input}"
      { value: input[:value] * 3, step: :three, final: true }
    end
  end

  class TestWorkflowWithCallbacks
    include Workflow

    step :step_one
    step :step_two

    attr_reader :execution_log, :step_timings

    def initialize
      @execution_log = []
      @step_timings = {}
    end

    def run_workflow_with_callbacks
      execute
    end

    private

    def step_one(input)
      @execution_log << "step_one with #{input.inspect}"
      { value: 2, step: :one }
    end

    def step_two(input)
      @execution_log << "step_two with #{input}"
      { value: input[:value] + 1, step: :two }
    end

    def after_step(output)
      @execution_log << "after #{current_step}"
      @step_timings[current_step] = Time.current
    end
  end

  class TestWorkflowWithoutInput
    include Workflow

    step :step_without_input

    attr_reader :execution_log

    def initialize
      @execution_log = []
    end

    def run_workflow_without_initial_input
      execute
    end

    private

    def step_without_input(input)
      @execution_log << "step_without_input with #{input.inspect}"
      { created_value: 42 }
    end
  end

  test "#execute should run steps in sequence with data flow" do
    service = TestWorkflow.new

    result = service.run_simple_workflow

    expected_log = [
      "step_one with nil",
      "step_two with {value: 2, step: :one}",
      "step_three with {value: 3, step: :two}"
    ]
    assert_equal expected_log, service.execution_log

    assert_equal({ value: 9, step: :three, final: true }, result)
  end

  test "#execute should run after callbacks" do
    service = TestWorkflowWithCallbacks.new

    result = service.run_workflow_with_callbacks

    expected_log = [
      "step_one with nil",
      "after step_one",
      "step_two with {value: 2, step: :one}",
      "after step_two"
    ]
    assert_equal expected_log, service.execution_log

    assert service.step_timings.key?(:step_one)
    assert service.step_timings.key?(:step_two)
    assert_kind_of Time, service.step_timings[:step_one]
  end

  test "#execute should handle workflows without initial input" do
    service = TestWorkflowWithoutInput.new

    result = service.run_workflow_without_initial_input

    assert_equal ["step_without_input with nil"], service.execution_log
    assert_equal({ created_value: 42 }, result)
  end

  test "#execute should propagate exceptions with clean backtrace" do
    service = TestWorkflow.new

    def service.step_one(input)
      @execution_log << "step_one called"
      raise StandardError, "Test error in step_one"
    end

    error = assert_raises(StandardError) do
      service.run_simple_workflow
    end

    assert_equal "Test error in step_one", error.message
    assert_equal ["step_one called"], service.execution_log
  end

  test "#execute should return nil when no steps are defined" do
    empty_service_class = Class.new do
      include Workflow
    end

    service = empty_service_class.new
    result = service.execute

    assert_nil result
  end

  test ".workflow_steps should list configured steps" do
    assert_equal [:step_one, :step_two, :step_three], TestWorkflow.workflow_steps
    assert_equal [:step_one, :step_two], TestWorkflowWithCallbacks.workflow_steps
    assert_equal [:step_without_input], TestWorkflowWithoutInput.workflow_steps
  end

  test "#step_durations should track durations automatically" do
    service = TestWorkflowWithCallbacks.new

    service.execute

    durations = service.step_durations
    assert durations.key?(:step_one)
    assert durations.key?(:step_two)

    assert_kind_of Float, durations[:step_one]
    assert_kind_of Float, durations[:step_two]
  end

  test "#step_durations should be recorded before after_step runs" do
    service = TestWorkflowWithCallbacks.new
    seen = {}
    service.define_singleton_method(:after_step) do |_output|
      seen[current_step] = step_durations[current_step]
    end

    service.execute

    assert_equal [:step_one, :step_two], seen.keys
    seen.each do |step, duration|
      assert_kind_of Float, duration, "#{step} duration must be recorded before after_step runs"
      assert_operator duration, :>=, 0
    end
  end

  test "#current_step should be accessible in callbacks" do
    service = TestWorkflowWithCallbacks.new

    service.execute

    assert_equal [:step_one, :step_two], service.step_timings.keys
    assert_equal :step_two, service.current_step
  end

  test "#total_duration should aggregate step timings" do
    service = TestWorkflowWithCallbacks.new

    service.execute

    total = service.total_duration
    assert_kind_of Float, total

    step_one_duration = service.step_durations[:step_one]
    step_two_duration = service.step_durations[:step_two]

    assert total >= step_one_duration, "total should cover each step's duration"
    assert total >= step_two_duration, "total should cover each step's duration"
  end
end
