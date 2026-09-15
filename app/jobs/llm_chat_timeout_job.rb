class LlmChatTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param chat_id [String] UUID of the interaction whose deadline was scheduled
  def perform(chat_id)
    LlmChat.find_by(id: chat_id)&.timeout!
  end
end
