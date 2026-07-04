# Live-qualifies the shipped Anthropic provider on the current default
# (Sonnet) model. See LlmCapabilityProbeJob.
class AnthropicCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "anthropic".freeze
  MODEL = "claude-sonnet-4-6".freeze
end
