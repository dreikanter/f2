require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  class TestService
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

  class TestServiceWithCallbacks
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

    def before_step(step_name, input)
      @execution_log << "before #{step_name}"
      @step_timings[step_name] = { started_at: Time.current }
    end

    def after_step(step_name, output)
      @execution_log << "after #{step_name}"
      @step_timings[step_name][:completed_at] = Time.current
    end
  end

  class TestServiceWithoutInput
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
    service = TestService.new

    result = service.run_simple_workflow

    expected_log = [
      "step_one with {:value=>1}",
      "step_two with {:value=>2, :step=>:one}",
      "step_three with {:value=>3, :step=>:two}"
    ]
    assert_equal expected_log, service.execution_log

    assert_equal({ value: 9, step: :three, final: true }, result)
  end

  test "executes before and after callbacks" do
    service = TestServiceWithCallbacks.new

    result = service.run_workflow_with_callbacks

    expected_log = [
      "before step_one",
      "step_one with {:value=>1}",
      "after step_one",
      "before step_two",
      "step_two with {:value=>2, :step=>:one}",
      "after step_two"
    ]
    assert_equal expected_log, service.execution_log

    assert service.step_timings.key?(:step_one)
    assert service.step_timings.key?(:step_two)
    assert service.step_timings[:step_one][:started_at]
    assert service.step_timings[:step_one][:completed_at]
  end

  test "handles workflow without initial input" do
    service = TestServiceWithoutInput.new

    result = service.run_workflow_without_initial_input

    assert_equal ["step_without_input with nil"], service.execution_log
    assert_equal({ created_value: 42 }, result)
  end

  test "propagates exceptions with clean backtrace" do
    service = TestService.new

    def service.step_one(input)
      @execution_log << "step_one called"
      raise StandardError, "Test error in step_one"
    end

    error = assert_raises(StandardError) do
      service.run_simple_workflow
    end

    assert_equal "Test error in step_one", error.message
    assert_equal ["step_one called"], service.execution_log

    backtrace_methods = error.backtrace.select { |line| line.include?("workflow_test.rb") }
    assert backtrace_methods.any? { |line| line.include?("step_one") }
    assert backtrace_methods.any? { |line| line.include?("run_simple_workflow") }
  end

  test "workflow with no steps returns initial input" do
    empty_service_class = Class.new do
      include Workflow

      def initialize
      end
    end

    service = empty_service_class.new
    result = service.execute({ initial: :data })

    assert_equal({ initial: :data }, result)
  end

  test "class-level step definitions are accessible" do
    assert_equal [:step_one, :step_two, :step_three], TestService.workflow_steps
    assert_equal [:step_one, :step_two], TestServiceWithCallbacks.workflow_steps
    assert_equal [:step_without_input], TestServiceWithoutInput.workflow_steps
  end

  test "tracks current step during execution" do
    service = TestServiceWithCallbacks.new

    captured_steps = []

    def service.step_one(input)
      @captured_steps ||= []
      @captured_steps << current_step
      { value: input[:value] * 2 }
    end

    def service.step_two(input)
      @captured_steps ||= []
      @captured_steps << current_step
      { value: input[:value] + 1 }
    end

    def service.captured_steps
      @captured_steps || []
    end

    service.execute({ value: 1 })

    assert_equal [:step_one, :step_two], service.captured_steps

    assert_equal :step_two, service.current_step
  end

  test "tracks step durations automatically" do
    service = TestServiceWithCallbacks.new

    service.execute({ value: 1 })

    durations = service.step_durations
    assert durations.key?(:step_one)
    assert durations.key?(:step_two)

    assert durations[:step_one].is_a?(Numeric)
    assert durations[:step_two].is_a?(Numeric)
    assert durations[:step_one] >= 0
    assert durations[:step_two] >= 0
  end

  test "step durations are empty before workflow execution" do
    service = TestServiceWithCallbacks.new

    assert_equal({}, service.step_durations)
    assert_nil service.current_step
    assert_equal 0.0, service.total_duration
  end

  test "current step tracking works with callbacks" do
    service = TestServiceWithCallbacks.new
    captured_current_steps = []

    def service.before_step(step_name, input)
      @captured_current_steps ||= []
      @captured_current_steps << { callback: :before, step_name: step_name, current_step: current_step }
    end

    def service.after_step(step_name, output)
      @captured_current_steps ||= []
      @captured_current_steps << { callback: :after, step_name: step_name, current_step: current_step }
    end

    def service.captured_current_steps
      @captured_current_steps || []
    end

    service.run_workflow_with_callbacks

    expected_captures = [
      { callback: :before, step_name: :step_one, current_step: :step_one },
      { callback: :after, step_name: :step_one, current_step: :step_one },
      { callback: :before, step_name: :step_two, current_step: :step_two },
      { callback: :after, step_name: :step_two, current_step: :step_two }
    ]

    assert_equal expected_captures, service.captured_current_steps
  end

  test "tracks total workflow duration" do
    service = TestServiceWithCallbacks.new

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
