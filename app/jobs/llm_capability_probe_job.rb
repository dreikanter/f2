# Base for the per-provider capability probe jobs (spec 005 §5; issue #913).
# Subclasses pin one (provider, model) pair via PROVIDER/MODEL. Everything the
# research needs lands in JobRun events: one event per check with full
# evidence, plus a summary verdict — no files to chase afterwards. If the
# provider has no API key in the environment, the run records a skip and ends.
class LlmCapabilityProbeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  def perform
    provider_key = self.class::PROVIDER
    model = self.class::MODEL

    unless LlmCapabilityProbe::Provider.configured?(provider_key)
      record_event(type: "job.llm_capability_probe.skipped",
                   message: "#{provider_key}/#{model}: no API key in environment",
                   level: :warning, provider: provider_key, model: model)
      return
    end

    probe(provider_key, model)
  end

  private

  def probe(provider_key, model)
    provider = LlmCapabilityProbe::Provider.build(provider_key)
    outcome = LlmCapabilityProbe::Runner.new(provider: provider, model: model).run

    outcome[:results].each do |result|
      record_event(type: "job.llm_capability_probe.check",
                   message: "#{result[:check]}: #{result[:status]} (#{result[:seconds]}s) — #{result[:note]}",
                   level: result[:status] == "FAIL" ? :warning : :info,
                   provider: provider_key, model: model, **result)
    end

    summary = outcome[:results].map { |r| "#{r[:check]}=#{r[:status]}" }.join(" ")
    record_event(type: "job.llm_capability_probe.completed",
                 message: "#{provider_key}/#{model}: #{summary}",
                 level: outcome[:passed] ? :info : :warning,
                 provider: provider_key, model: model, passed: outcome[:passed])
  end
end
