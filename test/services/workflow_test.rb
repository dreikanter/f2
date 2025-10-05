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
      execute({ value: 1 })
    end

    private

    def step_one(input)
      @execution_log << "step_one with #{input}"
      { value: input[:value] * 2, step: :one }
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
      execute({ value: 1 })
    end

    private

    def step_one(input)
      @execution_log << "step_one with #{input}"
      { value: input[:value] * 2, step: :one }
    end

    def step_two(input)
      @execution_log << "step_two with #{input}"
      { value: input[:value] + 1, step: :two }
    end

    def before_step(input)
      @execution_log << "before #{current_step}"
      @step_timings[current_step] = { started_at: Time.current }
    end

    def after_step(output)
      @execution_log << "after #{current_step}"
      @step_timings[current_step][:completed_at] = Time.current
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

  test "executes workflow steps in sequence with data flow" do
    service = TestWorkflow.new

    result = service.run_simple_workflow

    expected_log = [
      "step_one with {value: 1}",
      "step_two with {value: 2, step: :one}",
      "step_three with {value: 3, step: :two}"
    ]
    assert_equal expected_log, service.execution_log

    assert_equal({ value: 9, step: :three, final: true }, result)
  end

  test "executes before and after callbacks" do
    service = TestWorkflowWithCallbacks.new

    result = service.run_workflow_with_callbacks

    expected_log = [
      "before step_one",
      "step_one with {value: 1}",
      "after step_one",
      "before step_two",
      "step_two with {value: 2, step: :one}",
      "after step_two"
    ]
    assert_equal expected_log, service.execution_log

    assert service.step_timings.key?(:step_one)
    assert service.step_timings.key?(:step_two)
    assert service.step_timings[:step_one][:started_at]
    assert service.step_timings[:step_one][:completed_at]
  end

  test "handles workflow without initial input" do
    service = TestWorkflowWithoutInput.new

    result = service.run_workflow_without_initial_input

    assert_equal ["step_without_input with nil"], service.execution_log
    assert_equal({ created_value: 42 }, result)
  end

  test "propagates exceptions with clean backtrace" do
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

  test "workflow with no steps returns initial input" do
    empty_service_class = Class.new do
      include Workflow
    end

    service = empty_service_class.new
    result = service.execute("INITIAL")

    assert_equal("INITIAL", result)
  end

  test "class-level step definitions are accessible" do
    assert_equal [:step_one, :step_two, :step_three], TestWorkflow.workflow_steps
    assert_equal [:step_one, :step_two], TestWorkflowWithCallbacks.workflow_steps
    assert_equal [:step_without_input], TestWorkflowWithoutInput.workflow_steps
  end

  test "tracks step durations automatically" do
    service = TestWorkflowWithCallbacks.new

    service.execute({ value: 1 })

    durations = service.step_durations
    assert durations.key?(:step_one)
    assert durations.key?(:step_two)

    assert durations[:step_one].is_a?(Numeric)
    assert durations[:step_two].is_a?(Numeric)
    assert durations[:step_one] >= 0
    assert durations[:step_two] >= 0
  end

  test "current step is accessible in callbacks" do
    service = TestWorkflowWithCallbacks.new

    def service.before_step(input)
      @captured_steps ||= []
      @captured_steps << current_step
    end

    def service.after_step(output)
      # Override to prevent timing hash access errors
    end

    def service.captured_steps
      @captured_steps || []
    end

    service.execute({ value: 1 })

    assert_equal [:step_one, :step_two], service.captured_steps
    assert_equal :step_two, service.current_step
  end

  test "tracks total workflow duration" do
    service = TestWorkflowWithCallbacks.new

    service.execute({ value: 1 })

    total = service.total_duration
    assert total >= 0
    assert total.is_a?(Numeric)

    step_one_duration = service.step_durations[:step_one]
    step_two_duration = service.step_durations[:step_two]

    assert total >= step_one_duration
    assert total >= step_two_duration
  end
end
