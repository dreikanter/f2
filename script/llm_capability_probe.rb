# frozen_string_literal: true

# CLI for LlmCapabilityProbe (see app/services/llm_capability_probe.rb).
# The dev-area jobs runner (LlmCapabilityProbeJob) is the primary way to run
# the probe; this wrapper covers local one-off runs against a single pair.
#
# Usage:
#   bundle exec ruby script/llm_capability_probe.rb --user me@example.com --provider anthropic --model claude-sonnet-4-6
#   bundle exec ruby script/llm_capability_probe.rb --user me@example.com --provider moonshot --model kimi-k2.6 --checks models
#
# The key comes from that user's AI credential named after the probe (see
# LlmCapabilityProbe.credential_name); --user is what the dev area gets from
# the session and the CLI has to be told.

require "optparse"
require_relative "../config/environment"

options = { checks: LlmCapabilityProbe::Runner::CHECKS }
OptionParser.new do |parser|
  parser.on("--user EMAIL", "Owner of the probe credential") { |v| options[:user] = v }
  parser.on("--provider KEY", "#{LlmProvider.names.join(' | ')}") { |v| options[:provider] = v }
  parser.on("--model ID", "Model id as the provider names it") { |v| options[:model] = v }
  parser.on("--checks LIST", "Comma-separated subset of: #{LlmCapabilityProbe::Runner::CHECKS.join(',')}") do |v|
    options[:checks] = v.split(",").map(&:strip) & LlmCapabilityProbe::Runner::CHECKS
  end
end.parse!
abort "Required: --user, --provider and --model" unless options[:user] && options[:provider] && options[:model]

user = User.find_by(email_address: options[:user]) || abort("No user with email #{options[:user]}")
credential = LlmCapabilityProbe.credential_for(options[:provider], user: user) ||
             abort("#{options[:user]}: #{LlmCapabilityProbe.missing_credential_message(options[:provider])}")

runner = LlmCapabilityProbe::Runner.new(credential: credential, model: options[:model], checks: options[:checks])
outcome = runner.run

puts "\n#{credential.provider} / #{options[:model]} (#{credential.display_name})"
outcome[:results].each { |r| puts format("  %-11s %-4s %5ss  %s", r[:check], r[:status], r[:seconds], r[:note]) }
puts JSON.pretty_generate(outcome[:results])
exit(outcome[:passed] ? 0 : 1)
