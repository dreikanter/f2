class ResendWebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token
  before_action :verify_signature!

  def create
    event_type = params[:type]
    event = ResendWebhookEvent.new(params[:data])

    case event_type
    when "email.bounced"
      handle_bounced(event)
    when "email.complained"
      handle_complained(event)
    when "email.failed"
      handle_failed(event)
    when "email.sent"
      handle_sent(event)
    when "email.delivered"
      handle_delivered(event)
    when "email.delivery_delayed"
      handle_delayed(event)
    when "email.opened"
      handle_opened(event)
    when "email.clicked"
      handle_clicked(event)
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

  def handle_bounced(event)
    user, matched_field = find_user_by_email(event.recipient_email)
    return unless user

    handle_email_failure(user, matched_field, "bounced")
    EmailBouncedEvent.create(user: user, data: event.raw_data)
  end

  def handle_complained(event)
    user, matched_field = find_user_by_email(event.recipient_email)
    return unless user

    handle_email_failure(user, matched_field, "complained")
    EmailComplainedEvent.create(user: user, data: event.raw_data)
  end

  def handle_failed(event)
    user, matched_field = find_user_by_email(event.recipient_email)
    return unless user

    handle_email_failure(user, matched_field, "failed")
    EmailFailedEvent.create(user: user, data: event.raw_data)
  end

  def handle_sent(event)
    user, _matched_field = find_user_by_email(event.recipient_email)
    EmailSentEvent.create(user: user, data: event.raw_data)
  end

  def handle_delivered(event)
    user, _matched_field = find_user_by_email(event.recipient_email)
    EmailDeliveredEvent.create(user: user, data: event.raw_data)
  end

  def handle_delayed(event)
    user, _matched_field = find_user_by_email(event.recipient_email)
    EmailDelayedEvent.create(user: user, data: event.raw_data)
  end

  def handle_opened(event)
    user, _matched_field = find_user_by_email(event.recipient_email)
    EmailOpenedEvent.create(user: user, data: event.raw_data)
  end

  def handle_clicked(event)
    user, _matched_field = find_user_by_email(event.recipient_email)
    EmailClickedEvent.create(user: user, data: event.raw_data)
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
