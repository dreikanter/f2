class WorkflowContext
  attr_accessor :current_step
  attr_reader :stats

  def initialize(initial_data = {})
    @data = initial_data
    @stats = FeedRefreshEvent.default_stats
    @timers = {}
  end

  # Dynamic attribute access
  def method_missing(method_name, *args, &block)
    if method_name.to_s.end_with?("=")
      attr_name = method_name.to_s.chomp("=").to_sym
      @data[attr_name] = args.first
    elsif @data.key?(method_name)
      @data[method_name]
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s.end_with?("=") || @data.key?(method_name) || super
  end

  # Stats management
  def record_stats(new_stats = {})
    @stats.merge!(new_stats)
  end

  # Timer management
  def start_timer(name)
    @timers[name] = Time.current
  end

  def end_timer(name, allow_missing: false)
    start_time = @timers.delete(name)
    return 0.0 if start_time.nil? && allow_missing

    raise "Timer #{name} not found" if start_time.nil?

    Time.current - start_time
  end

  # Logging helpers
  def log_info(message)
    Rails.logger.info message
  end

  def log_error(message)
    Rails.logger.error message
  end
end
