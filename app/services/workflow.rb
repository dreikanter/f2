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
  attr_reader :current_step

  module ClassMethods
    def step(step_name)
      workflow_steps << step_name
    end

    def workflow_steps
      @workflow_steps ||= []
    end
  end

  def execute(initial_input = nil)
    workflow_start_time = Time.current
    steps = self.class.workflow_steps
    current_input = initial_input

    begin
      steps.each do |step_name|
        @current_step = step_name
        start_step_timer(step_name)
        before_step(step_name, current_input)

        current_input = send(step_name, current_input)

        after_step(step_name, current_input)
        end_step_timer(step_name)
      end

      @total_workflow_duration = Time.current - workflow_start_time

      current_input
    rescue StandardError => e
      @total_workflow_duration = Time.current - workflow_start_time
      on_error(e)
    end
  end

  def step_durations
    @step_durations ||= {}
  end

  def total_duration
    @total_workflow_duration || 0.0
  end

  private

  def before_step(_input)
    # Override
  end

  def after_step(_result)
    # Override
  end

  def on_error(_error)
    # Override
  end

  def start_step_timer(step_name)
    workflow_timers[step_name] = Time.current
  end

  def end_step_timer(step_name)
    start_time = workflow_timers.delete(step_name)
    return 0.0 if start_time.nil?

    duration = Time.current - start_time
    step_durations[step_name] = duration
    duration
  end

  def workflow_timers
    @workflow_timers ||= {}
  end
end
