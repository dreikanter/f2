# Base for the per-provider capability probe jobs. Subclasses pin one
# (provider, model) pair via PROVIDER/MODEL. Everything the research needs
# lands in JobRun events: one event per check with full evidence, plus a
# summary verdict — no files to chase afterwards.
#
# The key comes from an AiCredential named after the job and owned by whoever
# launched the run. Without that record the run says which credential to create
# and ends.
class LlmCapabilityProbeJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob
  include ProbesProviderCapability

  queue_as :default

  def self.credential_scope(user) = user.ai_credentials

  def self.credential_noun = "AI credential"

  def self.provider_label = LlmProvider.find(self::PROVIDER).display_name

  def self.description
    helpers.safe_join([
      "Runs the capability checks for #{self::MODEL} against the live #{provider_label} API. " \
      "Needs an #{credential_noun} named ",
      helpers.tag.code(credential_name),
      " on your own account."
    ])
  end

  def perform(user)
    provider_key = self.class::PROVIDER
    model = self.class::MODEL
    credential = self.class.credential_for(user)

    if credential.nil?
      record_event(type: "job.llm_capability_probe.skipped",
                   message: "#{provider_key}/#{model}: #{self.class.missing_credential_message}",
                   level: :warning, provider: provider_key, model: model,
                   expected_credential_name: self.class.credential_name)
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
