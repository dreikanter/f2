# Base for the per-provider capability probe jobs. Subclasses pin one
# (provider, model) pair via PROVIDER/MODEL. Everything the research needs
# lands in JobRun events: one event per check with full evidence, plus a
# summary verdict — no files to chase afterwards.
#
# The key comes from an AiCredential named after the probe and owned by whoever
# launched the run. Without that record the run says which credential to create
# and ends.
class LlmCapabilityProbeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  def self.description
    "Runs the capability checks for #{self::MODEL} against the live #{self::PROVIDER} API. " \
      "Needs an AI credential named “#{LlmCapabilityProbe.credential_name(self::PROVIDER)}” on your own account."
  end

  def self.runnable_arguments(user) = [user]

  def perform(user)
    provider_key = self.class::PROVIDER
    model = self.class::MODEL
    credential = LlmCapabilityProbe.credential_for(provider_key, user: user)

    if credential.nil?
      record_event(type: "job.llm_capability_probe.skipped",
                   message: "#{provider_key}/#{model}: #{LlmCapabilityProbe.missing_credential_message(provider_key)}",
                   level: :warning, provider: provider_key, model: model,
                   expected_credential_name: LlmCapabilityProbe.credential_name(provider_key))
      return
    end

    probe(provider_key, model, credential)
  end

  private

  def probe(provider_key, model, credential)
    outcome = LlmCapabilityProbe::Runner.new(credential: credential, model: model).run

    outcome[:results].each do |result|
      record_event(type: "job.llm_capability_probe.check",
                   message: "#{result[:check]}: #{result[:status]} (#{result[:seconds]}s) — #{result[:note]}",
                   level: result[:status] == "FAIL" ? :warning : :info,
                   provider: provider_key, model: model, credential_id: credential.id, **result)
    end

    summary = outcome[:results].map { |r| "#{r[:check]}=#{r[:status]}" }.join(" ")
    record_event(type: "job.llm_capability_probe.completed",
                 message: "#{provider_key}/#{model}: #{summary}",
                 level: outcome[:passed] ? :info : :warning,
                 provider: provider_key, model: model, credential_id: credential.id,
                 passed: outcome[:passed])
  end
end
