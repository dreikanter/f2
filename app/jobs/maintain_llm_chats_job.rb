class MaintainLlmChatsJob < ApplicationJob
  queue_as :default

  def perform
    LlmChat.overdue.find_each(batch_size: 500) do |chat|
      chat.finish!(status: :interrupted, error_category: "deadline_exceeded")
    end

    LlmChat.expired.find_each(batch_size: 500, &:destroy!)
  end
end
