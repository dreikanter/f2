module WorkflowExecutor
  def execute_workflow(initial_context = {}, &block)
    context = WorkflowContext.new(initial_context)
    steps = []

    # Collect steps from block
    step_collector = StepCollector.new
    step_collector.instance_eval(&block)
    steps = step_collector.steps

    # Execute steps
    current_step = nil
    begin
      steps.each do |step_name|
        current_step = step_name
        context.current_step = step_name
        send(step_name, context)
      end
      context
    rescue StandardError => e
      handle_workflow_error(context, current_step, e)
      raise
    end
  end

  private

  def handle_workflow_error(context, step_name, error)
    # Finalize partial stats
    context.record_stats(
      total_duration: context.end_timer(:total, allow_missing: true),
      failed_at_step: step_name
    )

    # Create error event
    FeedRefreshEvent.create_error(
      context.feed,
      error,
      step_name.to_s,
      context.stats
    )
  end

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
