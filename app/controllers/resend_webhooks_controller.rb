class ResendWebhooksController < ApplicationController
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
    svix_id = request.headers["svix-id"]
    svix_timestamp = request.headers["svix-timestamp"]
    svix_signature = request.headers["svix-signature"]

    unless svix_id && svix_timestamp && svix_signature
      head :unauthorized
      return
    end

    payload = request.raw_post
    expected_signature = compute_signature(svix_id, svix_timestamp, payload)

    signatures = svix_signature.split(" ")
    verified = signatures.any? do |versioned_sig|
      version, signature = versioned_sig.split(",", 2)
      next false unless version == "v1"

      ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
    end

    head :unauthorized unless verified
  end

  def compute_signature(msg_id, timestamp, payload)
    secret = Rails.application.credentials.dig(:resend, :webhook_secret)
    to_sign = "#{msg_id}.#{timestamp}.#{payload}"
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, to_sign))
  end

  def handle_bounced(data)
    user = find_user_by_email(data[:email])
    return unless user

    user.deactivate_email!(reason: "bounced")
    create_event("EmailBouncedEvent", user, data)
  end

  def handle_complained(data)
    user = find_user_by_email(data[:email])
    return unless user

    user.deactivate_email!(reason: "complained")
    create_event("EmailComplainedEvent", user, data)
  end

  def handle_failed(data)
    user = find_user_by_email(data[:email])
    return unless user

    user.deactivate_email!(reason: "failed")
    create_event("EmailFailedEvent", user, data)
  end

  def handle_sent(data)
    user = find_user_by_email(data[:to])
    create_event("EmailSentEvent", user, data)
  end

  def handle_delivered(data)
    user = find_user_by_email(data[:email])
    create_event("EmailDeliveredEvent", user, data)
  end

  def handle_delayed(data)
    user = find_user_by_email(data[:email])
    create_event("EmailDelayedEvent", user, data)
  end

  def handle_opened(data)
    user = find_user_by_email(data[:email])
    create_event("EmailOpenedEvent", user, data)
  end

  def handle_clicked(data)
    user = find_user_by_email(data[:email])
    create_event("EmailClickedEvent", user, data)
  end

  def find_user_by_email(email)
    return nil if email.blank?

    normalized_email = email.strip.downcase
    User.find_by(email_address: normalized_email)
  end

  def create_event(event_type, user, data)
    Event.create!(
      type: event_type,
      user: user,
      subject: user,
      metadata: data.to_h
    )
  end
end
