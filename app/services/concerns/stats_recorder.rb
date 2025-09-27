module StatsRecorder
  extend ActiveSupport::Concern

  included do
    attr_reader :stats
  end

  def initialize_stats
    @stats = {}
  end

  def record_stats(new_stats = {})
    stats.merge!(new_stats)
  end

  def record_duration(step_name)
    return unless respond_to?(:step_durations)

    duration = step_durations[step_name].to_f
    stats_key = step_stats_key(step_name)
    record_stats(stats_key => duration)
  end

  def step_stats_key(step_name)
    "#{step_name}_duration".to_sym
  end

  def record_timing_stats(started_at: nil, completed_at: nil)
    record_stats(started_at: started_at) if started_at
    record_stats(completed_at: completed_at) if completed_at

    if started_at && completed_at
      total_duration = completed_at - started_at
      record_stats(total_duration: total_duration)
    elsif completed_at && stats[:started_at]
      total_duration = completed_at - stats[:started_at]
      record_stats(total_duration: total_duration)
    end
  end

  def record_error_stats(error, current_step: nil)
    error_stats = { failed_at_step: current_step }
    error_stats[:total_duration] = total_duration if respond_to?(:total_duration)
    record_stats(error_stats)
  end
end