# Live-qualifies the Kimi candidate via Moonshot's OpenAI-compatible API.
# See LlmCapabilityProbeJob.
class KimiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "moonshot".freeze
  MODEL = "kimi-k2.5".freeze
end
