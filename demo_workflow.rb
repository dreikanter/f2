#!/usr/bin/env ruby

# Demo showing the new Workflow module with the exact API requested
require_relative "app/services/workflow"

class DemoService
  include Workflow

  def initialize
    @context = {
      user_name: "Alice",
      processing_start: Time.now,
      stats: {}
    }
  end

  def run_workflow
    puts "=== Starting Workflow Demo ==="

    # This is the exact API requested
    result = execute_workflow(
      { message: "Hello World" },
      before: :log_step_start,
      after: :log_step_end
    ) do |workflow|
      workflow.step :initialize_workflow
      workflow.step :load_feed_contents
      workflow.step :process_feed_contents
      workflow.step :persist_feed_entries
      workflow.step :normalize_feed_entries
      workflow.step :finalize_workflow
    end

    puts "=== Final Result: #{result} ==="
    result
  end

  private

  # Context is available via instance methods (not part of Workflow module)
  def current_user
    @context[:user_name]
  end

  def record_timing(step, duration)
    @context[:stats][step] = duration
  end

  def get_stats
    @context[:stats]
  end

  # Callback methods for timing/logging
  def log_step_start(step_name, input)
    @step_start_time = Time.now
    puts "  → Starting #{step_name} with input: #{input}"
  end

  def log_step_end(step_name, output)
    duration = Time.now - @step_start_time
    record_timing(step_name, duration)
    puts "  ← Completed #{step_name} in #{duration.round(3)}s, output: #{output}"
  end

  # Workflow steps - each receives input data and returns result data
  def initialize_workflow(input)
    puts "    Initializing workflow for user: #{current_user}"
    input.merge(status: :initialized, user: current_user)
  end

  def load_feed_contents(input)
    puts "    Loading feed contents..."
    # Simulate loading
    sleep(0.1)
    input.merge(
      raw_data: "<feed><item>Sample Item</item></feed>",
      content_size: 1024
    )
  end

  def process_feed_contents(input)
    puts "    Processing #{input[:content_size]} bytes of feed data..."
    # Simulate processing
    sleep(0.05)
    input.merge(
      processed_entries: [
        { uid: "item-1", title: "Sample Item", published_at: Time.now }
      ],
      total_entries: 1
    )
  end

  def persist_feed_entries(input)
    puts "    Persisting #{input[:total_entries]} entries..."
    # Simulate database operations
    sleep(0.02)
    input.merge(
      new_feed_entries: input[:processed_entries],
      new_entries_count: input[:total_entries]
    )
  end

  def normalize_feed_entries(input)
    puts "    Normalizing #{input[:new_entries_count]} entries..."
    # Simulate normalization
    sleep(0.03)
    input.merge(
      normalized_posts: input[:new_feed_entries],
      valid_posts: input[:new_entries_count],
      invalid_posts: 0
    )
  end

  def finalize_workflow(input)
    total_duration = Time.now - @context[:processing_start]
    puts "    Finalizing workflow (total duration: #{total_duration.round(3)}s)"

    final_stats = get_stats.merge(
      total_duration: total_duration,
      completed_at: Time.now
    )

    input.merge(
      status: :completed,
      final_stats: final_stats,
      summary: "Processed #{input[:valid_posts]} posts successfully"
    )
  end
end

# Demo with error handling
class ErrorDemoService
  include Workflow

  def run_workflow_with_error
    puts "\n=== Error Handling Demo ==="

    begin
      execute_workflow({ step: 1 }) do |workflow|
        workflow.step :step_one
        workflow.step :step_that_fails
        workflow.step :step_three  # This won't execute
      end
    rescue StandardError => e
      puts "Caught error: #{e.message}"
      puts "Backtrace shows clean call stack:"
      e.backtrace[0..3].each { |line| puts "  #{line}" }
    end
  end

  private

  def step_one(input)
    puts "  Step 1: Processing #{input[:step]}"
    input.merge(step: input[:step] + 1)
  end

  def step_that_fails(input)
    puts "  Step 2: About to fail..."
    raise StandardError, "Simulated workflow error at step 2"
  end

  def step_three(input)
    puts "  Step 3: This won't execute"
    input
  end
end

# Run the demos
if __FILE__ == $0
  # Normal workflow execution
  demo = DemoService.new
  demo.run_workflow

  # Error handling demo
  error_demo = ErrorDemoService.new
  error_demo.run_workflow_with_error

  puts "\n=== Demo Complete ==="
end
