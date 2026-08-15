# Base for the per-provider web-search probe jobs. Subclasses pin one provider
# via PROVIDER. Everything the diagnosis needs lands in JobRun events: one event
# per check with its evidence, plus a summary verdict.
#
# The key comes from a SearchCredential named after the probe (see
# SearchCapabilityProbe.credential_name). Without that record the run says which
# credential to create and ends.
class SearchCapabilityProbeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  def self.description
    "Runs the search checks against the live #{WebSearchProvider.label_for(self::PROVIDER)} API. " \
      "Needs a search credential named “#{SearchCapabilityProbe.credential_name(self::PROVIDER)}”, " \
      "and spends two queries on it."
  end

  def perform
    provider = self.class::PROVIDER
    credentials = SearchCapabilityProbe.candidate_credentials(provider).to_a

    return skip(provider, SearchCapabilityProbe.missing_credential_message(provider)) if credentials.empty?

    if credentials.many?
      return skip(provider, SearchCapabilityProbe.ambiguous_credential_message(provider, credentials.size))
    end

    probe(provider, credentials.sole)
  end

  private

  def skip(provider, reason)
    record_event(type: "job.search_capability_probe.skipped",
                 message: "#{provider}: #{reason}",
                 level: :warning, provider: provider,
                 expected_credential_name: SearchCapabilityProbe.credential_name(provider))
  end

  def probe(provider, credential)
    outcome = SearchCapabilityProbe::Runner.new(credential: credential).run

    outcome[:results].each do |result|
      record_event(type: "job.search_capability_probe.check",
                   message: "#{result[:check]}: #{result[:status]} (#{result[:seconds]}s) — #{result[:note]}",
                   level: result[:status] == "FAIL" ? :warning : :info,
                   provider: provider, credential_id: credential.id, **result)
    end

    summary = outcome[:results].map { |result| "#{result[:check]}=#{result[:status]}" }.join(" ")
    record_event(type: "job.search_capability_probe.completed",
                 message: "#{provider}: #{summary}",
                 level: outcome[:passed] ? :info : :warning,
                 provider: provider, credential_id: credential.id,
                 credential_state: credential.state, passed: outcome[:passed])
  end
end
