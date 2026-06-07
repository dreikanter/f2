require "net/http"
require "socket"

# Tiny push-based metrics client for VictoriaMetrics (or any Prometheus
# remote-import endpoint).
#
# Counters live in memory and are pushed periodically as their current
# cumulative total; gauges are sampled from a block at push time. A background
# thread flushes everything to METRICS_URL on an interval.
#
# Disabled (a no-op) unless METRICS_URL is set, so dev, test, and console runs
# are unaffected and instrumentation costs nothing there.
#
# Each process tags its counter series with an `instance` label (host:pid) so
# totals from multiple web/worker processes don't clobber each other — sum/max
# them at query time. Gauges are global snapshots, so they carry no instance.
#
# Configuration (ENV):
#   METRICS_URL            VM import endpoint, e.g.
#                          https://vm.example/api/v1/import/prometheus
#   METRICS_USERNAME       basic-auth user (optional)
#   METRICS_PASSWORD       basic-auth password (optional)
#   METRICS_FLUSH_INTERVAL seconds between pushes (default 15)
#   METRICS_INSTANCE       override the instance label (default host:pid)
#
# Keep label values low-cardinality (job, status, policy) — never per-user,
# per-subject, or per-id, which would blow up series count.
module Metrics
  PREFIX = "feeder_".freeze
  DEFAULT_FLUSH_INTERVAL = 15

  class << self
    def enabled?
      url.present?
    end

    def url
      ENV["METRICS_URL"].presence
    end

    # Bump a counter by `by` (default 1) for the given label set.
    def increment(name, by: 1, **labels)
      return unless enabled?

      key = [name.to_s, normalize_labels(labels)]
      mutex.synchronize { counters[key] += by }
    end

    # Register a gauge sampled at push time; the block returns the current value.
    def gauge(name, **labels, &block)
      gauges << [name.to_s, normalize_labels(labels), block]
    end

    # Everything currently known, as Prometheus exposition text.
    def render
      lines = []
      mutex.synchronize { counters.dup }.each do |(name, labels), value|
        lines << line(name, labels.merge("instance" => instance_label), value)
      end
      gauges.each do |name, labels, block|
        value = sample(block)
        lines << line(name, labels, value) unless value.nil?
      end
      "#{lines.join("\n")}\n"
    end

    # Push the current snapshot. Best-effort: errors are reported, never raised,
    # so a metrics outage can't take down the app.
    def flush!
      return unless enabled?

      body = render
      return if body.strip.empty?

      post(body)
    rescue => e
      Rails.error.report(e, context: { component: "metrics" })
    end

    # Start the background flusher. Call once per process (from an initializer).
    def start!(interval: flush_interval)
      return unless enabled?
      return if @thread&.alive?

      @thread = Thread.new do
        loop do
          sleep(interval)
          flush!
        end
      end
      @thread.name = "metrics-flusher"
      @thread
    end

    # Test seam: drop all recorded state.
    def reset!
      mutex.synchronize { counters.clear }
      gauges.clear
      @instance_label = nil
    end

    private

    def counters
      @counters ||= Hash.new(0)
    end

    def gauges
      @gauges ||= []
    end

    def mutex
      @mutex ||= Mutex.new
    end

    def flush_interval
      Integer(ENV.fetch("METRICS_FLUSH_INTERVAL", DEFAULT_FLUSH_INTERVAL))
    end

    def instance_label
      @instance_label ||= ENV["METRICS_INSTANCE"].presence || "#{Socket.gethostname}:#{Process.pid}"
    end

    def normalize_labels(labels)
      labels.to_h { |key, value| [key.to_s, value.to_s] }.sort.to_h
    end

    def sample(block)
      block.call
    rescue => e
      Rails.error.report(e, context: { component: "metrics", phase: "gauge_sample" })
      nil
    end

    def line(name, labels, value)
      prefixed = "#{PREFIX}#{name}"
      return "#{prefixed} #{value}" if labels.empty?

      inner = labels.map { |key, val| %(#{key}="#{escape(val)}") }.join(",")
      "#{prefixed}{#{inner}} #{value}"
    end

    def escape(value)
      value.gsub(/[\\"\n]/) { |char| { "\\" => "\\\\", '"' => '\"', "\n" => '\n' }[char] }
    end

    def post(body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Post.new(uri)
      request.body = body
      request.content_type = "text/plain"
      if (user = ENV["METRICS_USERNAME"].presence)
        request.basic_auth(user, ENV["METRICS_PASSWORD"].to_s)
      end

      http.request(request)
    end
  end
end
