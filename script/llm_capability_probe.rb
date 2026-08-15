# frozen_string_literal: true

# CLI for LlmCapabilityProbe (see app/services/llm_capability_probe.rb).
# The dev-area jobs runner (LlmCapabilityProbeJob) is the primary way to run
# the probe; this wrapper covers local one-off runs against a single pair.
#
# Usage:
#   bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job AnthropicCapabilityProbeJob
#   bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job KimiCapabilityProbeJob --model kimi-k3 --checks models
#
# The probe job is what names the credential and pins the pair, so the CLI takes
# one and borrows both; --model overrides the pinned model for a one-off pair.
# --user is what the dev area gets from the session and the CLI has to be told.

require "optparse"
require_relative "../config/environment"

probe_jobs = JobRun::RUNNABLE_JOBS.select { |job| job < LlmCapabilityProbeJob }

options = { checks: LlmCapabilityProbe::Runner::CHECKS }
OptionParser.new do |parser|
  parser.on("--user EMAIL", "Owner of the probe credential") { |v| options[:user] = v }
  parser.on("--job NAME", "#{probe_jobs.map(&:name).join(' | ')}") { |v| options[:job] = v }
  parser.on("--model ID", "Model id as the provider names it; defaults to the job's") { |v| options[:model] = v }
  parser.on("--checks LIST", "Comma-separated subset of: #{LlmCapabilityProbe::Runner::CHECKS.join(',')}") do |v|
    options[:checks] = v.split(",").map(&:strip) & LlmCapabilityProbe::Runner::CHECKS
  end
end.parse!
abort "Required: --user and --job" unless options[:user] && options[:job]

job_class = probe_jobs.find { |job| job.name == options[:job] } || abort("No probe job named #{options[:job]}")
model = options[:model] || job_class::MODEL
user = User.find_by(email_address: options[:user]) || abort("No user with email #{options[:user]}")
credential = job_class.credential_for(user) ||
             abort("#{options[:user]}: #{job_class.missing_credential_message}")

runner = LlmCapabilityProbe::Runner.new(credential: credential, model: model, checks: options[:checks])
outcome = runner.run

puts "\n#{credential.provider} / #{model} (#{credential.display_name})"
outcome[:results].each { |r| puts format("  %-11s %-4s %5ss  %s", r[:check], r[:status], r[:seconds], r[:note]) }
puts JSON.pretty_generate(outcome[:results])
exit(outcome[:passed] ? 0 : 1)
