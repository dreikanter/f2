class ResendWebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token
  before_action :verify_signature!

  EMAIL_EVENT_HANDLERS = {
    "email.bounced" => {
      action:     :handle_failure,
      level:      :warning,
      reason:     "bounced",
      event_type: "EmailBounced",
      message:    "Email bounced"
    },
    "email.complained" => {
      action:     :handle_failure,
      level:      :warning,
      reason:     "complained",
      event_type: "EmailComplained",
      message:    "Spam complaint"
    },
    "email.failed" => {
      action:     :handle_failure,
      level:      :error,
      reason:     "failed",
      event_type: "EmailFailed",
      message:    "Email failed"
    },
    "email.sent" => {
      action:     :track_only,
      level:      :info,
      event_type: "EmailSent",
      message:    "Email sent"
    },
    "email.delivered" => {
      action:     :track_only,
      level:      :info,
      event_type: "EmailDelivered",
      message:    "Email delivered"
    },
    "email.delivery_delayed" => {
      action:     :track_only,
      level:      :info,
      event_type: "EmailDelayed",
      message:    "Email delivery delayed"
    },
    "email.opened" => {
      action:     :track_only,
      level:      :info,
      event_type: "EmailOpened",
      message:    "Email opened"
    },
    "email.clicked" => {
      action:     :track_only,
      level:      :info,
      event_type: "EmailClicked",
      message:    "Email clicked"
    }
  }.freeze

  def create
    handler = EMAIL_EVENT_HANDLERS[params[:type]]
    return head :ok unless handler

    event = ResendWebhookEvent.new(params[:data])
    user, matched_field = find_user_by_email(event.recipient_email)

    handle_email_failure(user, matched_field, handler[:reason]) if handler[:action] == :handle_failure && user
    create_email_event(params[:type], user, event.raw_data, handler[:level], handler[:event_type], handler[:message]) if user

    head :ok
  end

  private

  def verify_signature!
    secret = Rails.application.credentials.resend_signing_secret
    return head :unauthorized if secret.blank?

    payload = request.raw_post

    headers = {
      "svix-id" => request.headers["svix-id"],
      "svix-timestamp" => request.headers["svix-timestamp"],
      "svix-signature" => request.headers["svix-signature"]
    }

    webhook = Svix::Webhook.new(secret)
    webhook.verify(payload, headers)
  rescue Svix::WebhookVerificationError
    head :unauthorized
  end

  def create_email_event(webhook_type, user, data, level, event_type, base_message)
    message = if user
      "#{base_message} for #{user.email_address}"
    else
      webhook_type
    end

    Event.create!(
      type: event_type,
      level: level,
      subject: user,
      user: user,
      message: message,
      metadata: data
    )
  end

  def find_user_by_email(email)
    return [nil, nil] if email.blank?

    normalized_email = email.strip.downcase

    user = User.find_by(email_address: normalized_email)
    return [user, :email_address] if user

    user = User.find_by(unconfirmed_email: normalized_email)
    return [user, :unconfirmed_email] if user

    [nil, nil]
  end

  def handle_email_failure(user, matched_field, reason)
    if matched_field == :email_address
      user.deactivate_email!(reason: reason)
    elsif matched_field == :unconfirmed_email
      user.update!(unconfirmed_email: nil)
    end
  end
end
