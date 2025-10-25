class ResendWebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token
  before_action :verify_signature!

  def create
    event_type = params[:type]
    event_data = params[:data]

    case event_type
    when "email.bounced"
      handle_bounced(event_data)
    when "email.complained"
      handle_complained(event_data)
    when "email.failed"
      handle_failed(event_data)
    when "email.sent"
      handle_sent(event_data)
    when "email.delivered"
      handle_delivered(event_data)
    when "email.delivery_delayed"
      handle_delayed(event_data)
    when "email.opened"
      handle_opened(event_data)
    when "email.clicked"
      handle_clicked(event_data)
    end

    head :ok
  end

  private

  def verify_signature!
    secret = Rails.application.credentials.resend_signing_secret
    payload = request.raw_post
    headers = {
      "svix-id" => request.headers["svix-id"],
      "svix-timestamp" => request.headers["svix-timestamp"],
      "svix-signature" => request.headers["svix-signature"]
    }

    wh = Svix::Webhook.new(secret)
    wh.verify(payload, headers)
  rescue Svix::WebhookVerificationError
    head :unauthorized
  end

  def handle_bounced(data)
    user, matched_field = find_user_by_email(data[:email])
    return unless user

    handle_email_failure(user, matched_field, "bounced")
    EmailBouncedEvent.create(user: user, data: data)
  end

  def handle_complained(data)
    user, matched_field = find_user_by_email(data[:email])
    return unless user

    handle_email_failure(user, matched_field, "complained")
    EmailComplainedEvent.create(user: user, data: data)
  end

  def handle_failed(data)
    user, matched_field = find_user_by_email(data[:email])
    return unless user

    handle_email_failure(user, matched_field, "failed")
    EmailFailedEvent.create(user: user, data: data)
  end

  def handle_sent(data)
    user, _matched_field = find_user_by_email(data[:to])
    EmailSentEvent.create(user: user, data: data)
  end

  def handle_delivered(data)
    user, _matched_field = find_user_by_email(data[:email])
    EmailDeliveredEvent.create(user: user, data: data)
  end

  def handle_delayed(data)
    user, _matched_field = find_user_by_email(data[:email])
    EmailDelayedEvent.create(user: user, data: data)
  end

  def handle_opened(data)
    user, _matched_field = find_user_by_email(data[:email])
    EmailOpenedEvent.create(user: user, data: data)
  end

  def handle_clicked(data)
    user, _matched_field = find_user_by_email(data[:email])
    EmailClickedEvent.create(user: user, data: data)
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
