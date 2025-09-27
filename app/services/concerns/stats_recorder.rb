module StatsRecorder
  extend ActiveSupport::Concern

  def stats
    @stats ||= {}
  end

  def record_stats(new_stats = {})
    stats.merge!(new_stats)
  end

  def record_started_at(time = Time.current)
    record_stats(started_at: time)
  end

  def record_completed_at(time = Time.current)
    record_stats(completed_at: time)
    calculate_total_duration if stats[:started_at]
  end

  private

  def calculate_total_duration
    return unless stats[:started_at] && stats[:completed_at]

    total_duration = stats[:completed_at] - stats[:started_at]
    record_stats(total_duration: total_duration)
  end

  def record_error_stats(error, current_step: nil)
    error_stats = { failed_at_step: current_step }
    error_stats[:total_duration] = total_duration if respond_to?(:total_duration)
    record_stats(error_stats)
  end
end
