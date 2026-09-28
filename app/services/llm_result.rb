# Carries AI response content and its chat between loader and processor.
class LlmResult
  class LifecycleError < StandardError; end

  attr_reader :content

  delegate :bytesize, to: :content
  delegate :fail!, :started_at, to: :chat

  def initialize(content:, chat:, run_id: chat.id)
    @content = content
    @chat = chat
    @run_id = run_id
  end

  def generated_uid(index)
    "llm:#{@run_id}:#{index}"
  end

  def complete!
    return true if chat.complete!

    raise LifecycleError, "AI extraction is no longer active."
  end

  private

  attr_reader :chat
end
