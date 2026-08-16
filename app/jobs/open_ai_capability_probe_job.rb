# Live-qualifies OpenAI on gpt-5.6-luna, the provider's default. See
# LlmCapabilityProbeJob.
class OpenAiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "openai".freeze
  MODEL = "gpt-5.6-luna".freeze
end
