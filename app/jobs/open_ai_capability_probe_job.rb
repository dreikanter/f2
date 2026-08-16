# Live-qualifies OpenAI on gpt-5-mini, cheap enough to re-run freely while the
# pair is being iterated on. See LlmCapabilityProbeJob.
class OpenAiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "openai".freeze
  MODEL = "gpt-5-mini".freeze
end
