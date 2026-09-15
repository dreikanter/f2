class MaintainLlmChatsJob < ApplicationJob
  queue_as :default

  def perform
    LlmChat.overdue.find_each(batch_size: 500, &:timeout!)

    LlmChat.expired.find_each(batch_size: 500, &:destroy!)
  end
end
