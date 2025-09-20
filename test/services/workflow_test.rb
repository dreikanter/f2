require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  class TestService
    include Workflow

    attr_reader :execution_log, :step_timings

    def initialize
      @execution_log = []
      @step_timings = {}
    end

    def run_simple_workflow
      execute_workflow({ value: 1 }) do |workflow|
        workflow.step :step_one
        workflow.step :step_two
        workflow.step :step_three
      end
    end

    def run_workflow_with_callbacks
      execute_workflow({ value: 1 }, before: :before_step, after: :after_step) do |workflow|
        workflow.step :step_one
        workflow.step :step_two
      end
    end

    def run_workflow_without_initial_input
      execute_workflow do |workflow|
        workflow.step :step_without_input
      end
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

    def step_without_input(input)
      @execution_log << "step_without_input with #{input.inspect}"
      { created_value: 42 }
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

  test "executes workflow steps in sequence with data flow" do
    service = TestService.new

    result = service.run_simple_workflow

    # Verify execution order and data flow
    expected_log = [
      "step_one with {:value=>1}",
      "step_two with {:value=>2, :step=>:one}",
      "step_three with {:value=>3, :step=>:two}"
    ]
    assert_equal expected_log, service.execution_log

    # Verify final result
    assert_equal({ value: 9, step: :three, final: true }, result)
  end

  test "executes before and after callbacks" do
    service = TestService.new

    result = service.run_workflow_with_callbacks

    # Verify callbacks were executed in correct order
    expected_log = [
      "before step_one",
      "step_one with {:value=>1}",
      "after step_one",
      "before step_two",
      "step_two with {:value=>2, :step=>:one}",
      "after step_two"
    ]
    assert_equal expected_log, service.execution_log

    # Verify timing data was collected
    assert service.step_timings.key?(:step_one)
    assert service.step_timings.key?(:step_two)
    assert service.step_timings[:step_one][:started_at]
    assert service.step_timings[:step_one][:completed_at]
  end

  test "handles workflow without initial input" do
    service = TestService.new

    result = service.run_workflow_without_initial_input

    assert_equal ["step_without_input with nil"], service.execution_log
    assert_equal({ created_value: 42 }, result)
  end

  test "propagates exceptions with clean backtrace" do
    service = TestService.new

    # Mock a step to raise an exception
    def service.step_one(input)
      @execution_log << "step_one called"
      raise StandardError, "Test error in step_one"
    end

    error = assert_raises(StandardError) do
      service.run_simple_workflow
    end

    assert_equal "Test error in step_one", error.message
    assert_equal ["step_one called"], service.execution_log

    # Verify the backtrace includes our workflow method
    backtrace_methods = error.backtrace.select { |line| line.include?("workflow_test.rb") }
    assert backtrace_methods.any? { |line| line.include?("step_one") }
    assert backtrace_methods.any? { |line| line.include?("run_simple_workflow") }
  end

  test "workflow with no steps returns initial input" do
    service = TestService.new

    result = service.execute_workflow({ initial: :data }) do |workflow|
      # No steps defined
    end

    assert_equal({ initial: :data }, result)
  end

  test "step collector properly accumulates steps" do
    collector = Workflow::StepCollector.new

    collector.step :first
    collector.step :second
    collector.step :third

    assert_equal [:first, :second, :third], collector.steps
  end
end
