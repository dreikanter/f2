# Carries AI response content and settles its persisted extraction outcome.
class LlmResult
  attr_reader :content

  delegate :bytesize, to: :content

  def initialize(content:, chat:)
    @content = content
    @chat = chat
  end

  # Only validated, current output may leave the processor for publication.
  def complete!
    return true if chat.finish!(status: :succeeded)

    chat.timeout!
    raise Loader::Error, "AI extraction is no longer active."
  end

  def fail!(error)
    chat.timeout!
    chat.finish!(status: :failed, error_category: error.class.name)
  end

  private

  attr_reader :chat
end
