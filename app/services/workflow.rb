# Minimal workflow execution module
#
# Usage:
#   class MyService
#     include Workflow
#
#     step :initialize_workflow
#     step :load_data
#     step :process_data
#     step :finalize_workflow
#
#     def initialize(initial_input)
#       @initial_input = initial_input
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
  def self.included(base)
    base.extend(ClassMethods)
    base.class_eval do
      @workflow_steps = []
    end
  end

  module ClassMethods
    def step(step_name)
      @workflow_steps ||= []
      @workflow_steps << step_name
    end

    def workflow_steps
      @workflow_steps || []
    end
  end

  def execute(initial_input = nil, before: nil, after: nil, on_error: nil)
    @workflow_timers = {}
    @workflow_start_time = Time.current

    steps = self.class.workflow_steps

    current_input = initial_input
    begin
      steps.each do |step_name|
        @current_step = step_name
        start_step_timer(step_name)

        send(before, step_name, current_input) if before

        current_input = send(step_name, current_input)

        send(after, step_name, current_input) if after

        end_step_timer(step_name)
      end

      @total_workflow_duration = Time.current - @workflow_start_time

      current_input
    rescue StandardError => e
      @total_workflow_duration = Time.current - @workflow_start_time

      send(on_error, e) if on_error

      raise
    end
  end

  def current_step
    @current_step
  end

  def step_durations
    @step_durations ||= {}
  end

  def total_duration
    @total_workflow_duration || 0.0
  end

  private

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
end
