# Base for the per-provider web-search probe jobs. Subclasses pin one provider
# via PROVIDER. Everything the diagnosis needs lands in JobRun events: one event
# per check with its evidence, plus a summary verdict.
#
# The key comes from a SearchCredential named after the job and owned by
# whoever launched the run, so a probe only ever spends its own operator's
# queries. Without that record the run says which credential to create and ends.
class SearchCapabilityProbeJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  queue_as :default

  # The credential wears the job's own class name, so what the dev area lists
  # is what to type into the credential form — no second naming to look up.
  def self.credential_name = name.delete_suffix("Job")

  # Scoped to whoever launched the probe: each run spends billed queries, and
  # display names are unique per user and provider, so the owner is what makes
  # the name resolve to one key.
  def self.credential_for(user)
    user.search_credentials.find_by(provider: self::PROVIDER, display_name: credential_name)
  end

  # Says what to create, since the fix is always the same: one credential, this
  # provider, this exact name.
  def self.missing_credential_message
    "no search credential named #{credential_name.inspect} on your account — " \
      "add a #{WebSearchProvider.label_for(self::PROVIDER)} credential with that exact name to run this probe"
  end

  def self.description
    helpers.safe_join([
      "Runs the search checks against the live #{WebSearchProvider.label_for(self::PROVIDER)} API. " \
      "Needs a search credential named ",
      helpers.tag.code(credential_name),
      " on your own account, and spends two queries on it."
    ])
  end

  def self.runnable_arguments(user) = [user]

  def perform(user)
    provider = self.class::PROVIDER
    credential = self.class.credential_for(user)

    return skip(provider, self.class.missing_credential_message) if credential.nil?

    probe(provider, credential)
  end

  private

  def skip(provider, reason)
    record_event(type: "job.search_capability_probe.skipped",
                 message: "#{provider}: #{reason}",
                 level: :warning, provider: provider,
                 expected_credential_name: self.class.credential_name)
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
