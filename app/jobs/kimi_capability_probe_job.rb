# Live-qualifies the Kimi candidate via Moonshot's OpenAI-compatible API.
# See LlmCapabilityProbeJob.
class KimiCapabilityProbeJob < LlmCapabilityProbeJob
  PROVIDER = "moonshot".freeze
  # kimi-k2.5 is retiring; k2.6 is the cost-faithful successor (k3 is priced at
  # flagship level, which would undo Kimi's reason for being here). Pointing the
  # probe first is deliberate — nothing else moves to k2.6 until a run qualifies
  # it, since the capability matrix is gated on probe evidence (#1187).
  MODEL = "kimi-k2.6".freeze
end
