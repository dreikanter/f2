class InterruptLlmUsagesJob < ApplicationJob
  queue_as :default

  def perform
    LlmUsage.overdue.find_each(batch_size: 500, &:interrupt!)
  end
end
