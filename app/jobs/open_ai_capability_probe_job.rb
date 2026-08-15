# Live-qualifies the OpenAI candidate on the provider's default model.
# See LlmCapabilityProbeJob.
class OpenAiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "openai".freeze
  MODEL = "gpt-5.4".freeze
end
