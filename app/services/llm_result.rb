# Carries AI response content and its chat between loader and processor.
class LlmResult
  class LifecycleError < StandardError; end

  attr_reader :content, :generation_id

  delegate :bytesize, to: :content
  delegate :fail!, to: :chat

  def initialize(content:, chat:, generation_id: chat.id)
    @content = content
    @chat = chat
    @generation_id = generation_id
  end

  def complete!
    return true if chat.complete!

    raise LifecycleError, "AI extraction is no longer active."
  end

  private

  attr_reader :chat
end
