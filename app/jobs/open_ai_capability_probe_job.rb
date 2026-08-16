# Live-qualifies the OpenAI provider on its default model. See
# LlmCapabilityProbeJob.
class OpenAiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "openai".freeze
  MODEL = "gpt-5.6-luna".freeze
end
