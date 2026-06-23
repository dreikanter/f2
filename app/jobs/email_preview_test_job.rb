# Delivers an email preview, rendered with sample data, to a single recipient
# so devs can see how a template looks in a real inbox. The sample sender has
# no user record, so it runs in sample_mode to skip Event registration while
# still using the real delivery backend.
class EmailPreviewTestJob < ApplicationJob
  queue_as :default

  def perform(preview_id, recipient)
    ApplicationMailer.sample_mode = true

    delivery = EmailPreview.delivery(preview_id)
    return unless delivery

    delivery.message.to = recipient
    delivery.deliver_now
  ensure
    ApplicationMailer.sample_mode = false
  end
end
