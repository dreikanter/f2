# frozen_string_literal: true

# CLI for RedditRetrievalProbe (see app/services/reddit_retrieval_probe.rb).
# The dev-area jobs runner (RedditRetrievalProbeJob) is the primary way to run
# this on the deployed host; this wrapper covers local one-off runs.
#
# Usage:
#   bundle exec ruby script/reddit_retrieval_probe.rb
#   bundle exec ruby script/reddit_retrieval_probe.rb --checks listing,rss_control
#
# Note: Reddit 403s unauthenticated requests from datacenter IPs, so a run from
# a blocked network (sandbox/CI) reports FAIL — that is the probe working, not a
# bug. Run it where the app is deployed to learn whether that egress is allowed.

require "optparse"
require_relative "../config/environment"

options = { checks: RedditRetrievalProbe::Runner::CHECKS }
OptionParser.new do |parser|
  parser.on("--checks LIST", "Comma-separated subset of: #{RedditRetrievalProbe::Runner::CHECKS.join(',')}") do |v|
    options[:checks] = v.split(",").map(&:strip) & RedditRetrievalProbe::Runner::CHECKS
  end
end.parse!

outcome = RedditRetrievalProbe.run(checks: options[:checks])

puts "\nReddit retrieval probe"
outcome[:results].each { |r| puts format("  %-12s %-4s %5ss  %s", r[:check], r[:status], r[:seconds], r[:note]) }
puts JSON.pretty_generate(outcome[:results])
exit(outcome[:passed] ? 0 : 1)
