require "time"

module Loader
  class Throttled < Error
    DEFAULT_RETRY_AFTER = 5.minutes

    attr_reader :source_host, :retry_after, :http_status

    def initialize(source_host:, retry_after:, http_status: nil)
      @source_host = source_host
      @retry_after = retry_after
      @http_status = http_status
      super("Source is rate limiting requests; try again later")
    end

    def self.from_response(response, source_host:)
      header = response.headers.find { |name, _| name.casecmp?("retry-after") }&.last.to_s.strip
      new(source_host: source_host, retry_after: retry_after_seconds(header), http_status: response.status)
    end

    def self.retry_after_seconds(header)
      seconds = header.match?(/\A\d+\z/) ? header.to_i : Time.httpdate(header) - Time.current
      seconds.positive? ? seconds : DEFAULT_RETRY_AFTER
    rescue ArgumentError
      DEFAULT_RETRY_AFTER
    end
    private_class_method :retry_after_seconds

    def details
      { source_host: source_host, http_status: http_status, retry_after: retry_after }.compact
    end
  end
end
