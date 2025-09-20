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
    # Collect step names
    collector = StepCollector.new
    collector.instance_eval(&block)
    steps = collector.steps

    # Execute steps sequentially
    current_input = initial_input
    steps.each do |step_name|
      # Execute before callback if provided
      send(before, step_name, current_input) if before

      # Execute the step - this preserves the call stack for clean backtraces
      current_input = send(step_name, current_input)

      # Execute after callback if provided
      send(after, step_name, current_input) if after
    end

    current_input
  end

  private

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
