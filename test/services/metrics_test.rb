require "test_helper"

# A throwaway job used to exercise the ApplicationJob metrics hook.
class MetricsProbeJob < ApplicationJob
  def perform(mode)
    raise RateLimit::Throttled.new(retry_after: 1) if mode == :throttle
    raise "boom" if mode == :error
  end
end

class MetricsTest < ActiveSupport::TestCase
  teardown do
    Metrics.reset!
    %w[METRICS_URL METRICS_USERNAME METRICS_PASSWORD METRICS_INSTANCE].each { |key| ENV.delete(key) }
  end

  def enable!(url: "https://vm.test/api/v1/import/prometheus")
    ENV["METRICS_URL"] = url
    ENV["METRICS_INSTANCE"] = "host:1"
  end

  test "#enabled? should be false without METRICS_URL" do
    assert_not Metrics.enabled?
  end

  test "#increment should be a no-op when disabled" do
    Metrics.increment("job_executions_total", status: "ok")

    refute_includes Metrics.render, "feeder_job_executions_total"
  end

  test "#render should emit a prefixed counter line with sorted labels and an instance" do
    enable!
    2.times { Metrics.increment("job_executions_total", job: "PostPublishJob", status: "ok") }

    assert_includes Metrics.render,
                    %(feeder_job_executions_total{job="PostPublishJob",status="ok",instance="host:1"} 2)
  end

  test "#increment should accumulate and honor by:" do
    enable!
    Metrics.increment("rate_limit_throttled_total", policy: "freefeed", by: 3)

    assert_includes Metrics.render, %(feeder_rate_limit_throttled_total{policy="freefeed",instance="host:1"} 3)
  end

  test "#gauge should be sampled at render time and carry no instance label" do
    enable!
    value = 5
    Metrics.gauge("feeds_enabled") { value }

    assert_includes Metrics.render, "feeder_feeds_enabled 5"
    value = 9
    assert_includes Metrics.render, "feeder_feeds_enabled 9"
  end

  test "#gauge_set should render a line per label set sampled at render time" do
    enable!
    sizes = { { table: "users" } => 100, { table: "feeds" } => 200 }
    Metrics.gauge_set("pg_table_size_bytes") { sizes }

    out = Metrics.render
    assert_includes out, %(feeder_pg_table_size_bytes{table="users"} 100)
    assert_includes out, %(feeder_pg_table_size_bytes{table="feeds"} 200)

    sizes = { { table: "users" } => 150 }
    assert_includes Metrics.render, %(feeder_pg_table_size_bytes{table="users"} 150)
  end

  test "#gauge_set should report sampling errors and emit nothing for that set" do
    enable!
    Metrics.gauge_set("pg_table_size_bytes") { raise "db down" }

    reported = []
    out = Rails.error.stub(:report, ->(err, **) { reported << err }) { Metrics.render }

    refute_includes out, "pg_table_size_bytes"
    assert_equal 1, reported.size
  end

  test "#render should escape quotes in label values" do
    enable!
    Metrics.increment("job_executions_total", job: 'a"b')

    assert_includes Metrics.render, 'job="a\"b"'
  end

  test "#flush! should POST exposition text to METRICS_URL with basic auth" do
    enable!
    ENV["METRICS_USERNAME"] = "u"
    ENV["METRICS_PASSWORD"] = "p"
    stub_request(:post, "https://vm.test/api/v1/import/prometheus").to_return(status: 204)
    Metrics.increment("job_executions_total", status: "ok")

    Metrics.flush!

    assert_requested(:post, "https://vm.test/api/v1/import/prometheus") do |req|
      req.headers["Authorization"] == "Basic #{Base64.strict_encode64("u:p")}" &&
        req.body.include?("feeder_job_executions_total")
    end
  end

  test "#flush! should log transport errors without reporting to error tracker" do
    enable!
    stub_request(:post, "https://vm.test/api/v1/import/prometheus").to_raise(Errno::ECONNREFUSED)
    Metrics.increment("job_executions_total", status: "ok")

    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      assert_nothing_raised { Metrics.flush! }
    end
    assert_empty reported, "transport errors must not reach the error tracker"
  end

  test "ApplicationJob should record job runs by outcome" do
    enable!

    MetricsProbeJob.perform_now(:ok)
    assert_raises(RateLimit::Throttled) { MetricsProbeJob.perform_now(:throttle) }
    assert_raises(RuntimeError) { MetricsProbeJob.perform_now(:error) }

    out = Metrics.render
    assert_includes out, %(feeder_job_executions_total{job="MetricsProbeJob",status="ok",instance="host:1"} 1)
    assert_includes out, %(feeder_job_executions_total{job="MetricsProbeJob",status="throttled",instance="host:1"} 1)
    assert_includes out, %(feeder_job_executions_total{job="MetricsProbeJob",status="error",instance="host:1"} 1)
  end
end
