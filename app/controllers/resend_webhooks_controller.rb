class ResendWebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token
  before_action :verify_signature!

  EMAIL_EVENT_HANDLERS = {
    "email.bounced" => {
      action: :handle_failure,
      level: :warning,
      reason: "bounced",
      type: "email_bounced",
      message: "Email bounced"
    },
    "email.complained" => {
      action: :handle_failure,
      level: :warning,
      reason: "complained",
      type: "email_complained",
      message: "Spam complaint"
    },
    "email.failed" => {
      action: :handle_failure,
      level: :error,
      reason: "failed",
      type: "email_failed",
      message: "Email failed"
    },
    "email.sent" => {
      action: :track_only,
      level: :info,
      type: "email_sent",
      message: "Email sent"
    },
    "email.delivered" => {
      action: :track_only,
      level: :info,
      type: "email_delivered",
      message: "Email delivered"
    },
    "email.delivery_delayed" => {
      action: :track_only,
      level: :info,
      type: "email_delayed",
      message: "Email delivery delayed"
    },
    "email.opened" => {
      action: :track_only,
      level: :info,
      type: "email_opened",
      message: "Email opened"
    },
    "email.clicked" => {
      action: :track_only,
      level: :info,
      type: "email_clicked",
      message: "Email clicked"
    }
  }.freeze

  def create
    handler = EMAIL_EVENT_HANDLERS[params[:type]]
    unless handler
      Rails.logger.info "Received unknown Resend event type: #{params[:type]}"
      return head :ok
    end

    event = ResendWebhookEvent.new(params[:data])
    user, matched_field = find_user_by_email(event.recipient_email)

    if handler[:action] == :handle_failure && user
      handle_email_failure(user, matched_field, handler[:reason])
    end

    if user
      event_attributes = handler.slice(:level, :type, :message)
      Event.create!(**event_attributes, subject: user, user: user, metadata: event.raw_data)
    else
      Rails.logger.debug "Skipping event #{handler[:type]} for unknown user: #{event.recipient_email}"
    end

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
