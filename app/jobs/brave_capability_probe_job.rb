# Probes the Brave integration against the Brave Search API. See
# SearchCapabilityProbeJob.
class BraveCapabilityProbeJob < SearchCapabilityProbeJob
  PROVIDER = "brave".freeze
end
