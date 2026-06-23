# Delivers an email preview, rendered with sample data, to a single recipient
# so devs can see how a template looks in a real inbox.
class EmailPreviewTestJob < ApplicationJob
  queue_as :default

  def perform(preview_id, recipient)
    delivery = EmailPreview.delivery(preview_id)
    return unless delivery

    delivery.message.to = recipient
    delivery.deliver_now
  end
end
