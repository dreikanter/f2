# Live-qualifies the candidate (provider, model) pairs for the AI engine
# (spec 005 §5; issue #913) and records each pair's check matrix as events
# on the JobRun. Pairs whose provider has no API key in the environment are
# skipped, so the job is safe to run anywhere; full transcripts land in
# tmp/llm_probe for the plan-03 verification record.
class LlmCapabilityProbeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  # Qualification targets, not the production allowlist: anthropic is the
  # shipped provider (re-confirm on the current default model), moonshot is
  # the Kimi candidate under evaluation.
  CANDIDATE_PAIRS = {
    "anthropic" => "claude-sonnet-4-6",
    "moonshot" => "kimi-k2.5"
  }.freeze

  def perform
    CANDIDATE_PAIRS.each do |provider_key, model|
      unless LlmCapabilityProbe::Provider.configured?(provider_key)
        record_event(type: "job.llm_capability_probe.skipped",
                     message: "#{provider_key}/#{model}: no API key in environment",
                     level: :warning, provider: provider_key, model: model)
        next
      end

      probe(provider_key, model)
    end
  end

  private

  def probe(provider_key, model)
    provider = LlmCapabilityProbe::Provider.build(provider_key)
    outcome = LlmCapabilityProbe::Runner.new(provider: provider, model: model).run
    summary = outcome[:results].map { |r| "#{r[:check]}=#{r[:status]}" }.join(" ")

    record_event(type: "job.llm_capability_probe.completed",
                 message: "#{provider_key}/#{model}: #{summary}",
                 level: outcome[:passed] ? :info : :warning,
                 provider: provider_key, model: model,
                 results: outcome[:results].map { |r| r.except(:evidence) },
                 transcript: outcome[:transcript_path])
  end
end
