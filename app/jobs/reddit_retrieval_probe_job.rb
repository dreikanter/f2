# Live-checks Reddit vote-data retrieval from the deployed environment and
# records the outcome as JobRun events. See RedditRetrievalProbe for what the
# checks establish. Launched from the dev-area jobs runner; takes no arguments.
class RedditRetrievalProbeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  def perform
    outcome = RedditRetrievalProbe.run

    outcome[:results].each do |result|
      record_event(type: "job.reddit_retrieval_probe.check",
                   message: "#{result[:check]}: #{result[:status]} (#{result[:seconds]}s) — #{result[:note]}",
                   level: result[:status] == "FAIL" ? :warning : :info,
                   **result)
    end

    summary = outcome[:results].map { |r| "#{r[:check]}=#{r[:status]}" }.join(" ")
    record_event(type: "job.reddit_retrieval_probe.completed",
                 message: summary,
                 level: outcome[:passed] ? :info : :warning,
                 passed: outcome[:passed])
  end
end
