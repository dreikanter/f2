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
  end

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

    steps.each do |step_name|
      @current_step = step_name
      start_step_timer(step_name)

      begin
        before_step(step_name, current_input)
        current_input = send(step_name, current_input)
        after_step(step_name, current_input)
      rescue => e
        on_error(step_name, e)
        raise
      end

      end_step_timer(step_name)
    end

    @total_duration = Time.current - workflow_start_time
    current_input
  end

  def step_durations
    @step_durations ||= {}
  end

  def total_duration
    @total_duration || 0.0
  end

  def logger
    Rails.logger
  end

  private

  def before_step(step_name, _input)
    logger.info "#{workflow_name}: Starting step: #{step_name}"
  end

  def after_step(step_name, _result)
    logger.info "#{workflow_name}: Completed step: #{step_name}"
  end

  def workflow_name
    @workflow_name ||= self.class.name
  end

  def on_error(step_name, error)
    # Override
  end

  def start_step_timer(step_name)
    step_timers[step_name] = Time.current
  end

  def end_step_timer(step_name)
    start_time = step_timers.delete(step_name)
    return 0.0 if start_time.nil?

    duration = Time.current - start_time
    step_durations[step_name] = duration
    duration
  end

  def step_timers
    @step_timers ||= {}
  end
end
