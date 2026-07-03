# frozen_string_literal: true

# CLI for LlmCapabilityProbe (see app/services/llm_capability_probe.rb).
# The dev-area jobs runner (LlmCapabilityProbeJob) is the primary way to run
# the probe; this wrapper covers local one-off runs against a single pair.
#
# Usage:
#   bundle exec ruby script/llm_capability_probe.rb --provider anthropic --model claude-sonnet-4-6
#   bundle exec ruby script/llm_capability_probe.rb --provider moonshot --model kimi-k2.5 --checks web_search,two_step
#
# Keys via env: ANTHROPIC_API_KEY, MOONSHOT_API_KEY (MOONSHOT_API_BASE to override).

require "optparse"
require_relative "../config/environment"

options = { checks: LlmCapabilityProbe::Runner::CHECKS }
OptionParser.new do |parser|
  parser.on("--provider KEY", "anthropic | moonshot") { |v| options[:provider] = v }
  parser.on("--model ID", "Model id as the provider names it") { |v| options[:model] = v }
  parser.on("--checks LIST", "Comma-separated subset of: #{LlmCapabilityProbe::Runner::CHECKS.join(',')}") do |v|
    options[:checks] = v.split(",").map(&:strip) & LlmCapabilityProbe::Runner::CHECKS
  end
end.parse!
abort "Required: --provider and --model" unless options[:provider] && options[:model]

provider = LlmCapabilityProbe::Provider.build(options[:provider])
runner = LlmCapabilityProbe::Runner.new(provider: provider, model: options[:model], checks: options[:checks])
outcome = runner.run

puts "\n#{provider.key} / #{options[:model]}"
outcome[:results].each { |r| puts format("  %-11s %-4s %5ss  %s", r[:check], r[:status], r[:seconds], r[:note]) }
puts "\nTranscript: #{outcome[:transcript_path]}"
exit(outcome[:passed] ? 0 : 1)
