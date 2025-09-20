# Minimal workflow execution module
#
# Usage:
#   class MyService
#     include Workflow
#
#     def run_workflow
#       result = execute_workflow(initial_input, before: :log_step, after: :track_time) do |workflow|
#         workflow.step :initialize_workflow
#         workflow.step :load_data
#         workflow.step :process_data
#         workflow.step :finalize_workflow
#       end
#     end
#
#     private
#
#     def initialize_workflow(input)
#       # Return data for next step
#       { status: :initialized, data: input }
#     end
#
#     def load_data(input)
#       # Process input from previous step, return data for next step
#       { data: load_some_data(input[:data]) }
#     end
#   end
module Workflow
  # Execute a workflow with a series of steps
  #
  # @param initial_input [Object] Optional initial input for the first step
  # @param before [Symbol] Optional callback method to call before each step
  # @param after [Symbol] Optional callback method to call after each step
  # @yield [collector] Block that defines the workflow steps
  # @return [Object] Result from the last step
  def execute_workflow(initial_input = nil, before: nil, after: nil, &block)
    # Initialize workflow tracking
    @workflow_timers = {}
    @workflow_start_time = Time.current

    # Collect step names
    collector = StepCollector.new
    collector.instance_eval(&block)
    steps = collector.steps

    # Execute steps sequentially
    current_input = initial_input
    steps.each do |step_name|
      # Track current step and start timer
      @current_step = step_name
      start_step_timer(step_name)

      # Execute before callback if provided
      send(before, step_name, current_input) if before

      # Execute the step - this preserves the call stack for clean backtraces
      current_input = send(step_name, current_input)

      # Execute after callback if provided
      send(after, step_name, current_input) if after

      # End timer and record duration
      end_step_timer(step_name)
    end

    # Record total workflow duration
    @total_workflow_duration = Time.current - @workflow_start_time

    current_input
  end

  # Access the current step being executed
  def current_step
    @current_step
  end

  # Get step durations recorded during workflow execution
  def step_durations
    @step_durations ||= {}
  end

  # Get total workflow duration (from start to end of execution)
  def total_duration
    @total_workflow_duration || 0.0
  end

  private

  # Timer management for workflow steps
  def start_step_timer(step_name)
    @workflow_timers[step_name] = Time.current
  end

  def end_step_timer(step_name)
    start_time = @workflow_timers.delete(step_name)
    return 0.0 if start_time.nil?

    duration = Time.current - start_time
    step_durations[step_name] = duration
    duration
  end

  # Internal helper to collect step definitions from the block
  class StepCollector
    attr_reader :steps

    def initialize
      @steps = []
    end

    def step(name)
      @steps << name
    end
  end
end
