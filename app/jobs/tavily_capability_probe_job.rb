# Probes the Tavily integration against tavily.com. See SearchCapabilityProbeJob.
class TavilyCapabilityProbeJob < SearchCapabilityProbeJob
  PROVIDER = "tavily".freeze
end
