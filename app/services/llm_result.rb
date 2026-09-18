# Carries AI response content and its chat between loader and processor.
class LlmResult
  class LifecycleError < StandardError; end

  attr_reader :content

  delegate :bytesize, to: :content
  delegate :fail!, to: :chat

  def initialize(content:, chat:)
    @content = content
    @chat = chat
  end

  def complete!
    return true if chat.complete!

    raise LifecycleError, "AI extraction is no longer active."
  end

  private

  attr_reader :chat
end
