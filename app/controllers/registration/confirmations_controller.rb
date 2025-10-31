class Registration::ConfirmationsController < ApplicationController
  layout "modal"

  allow_unauthenticated_access

  rate_limit to: 5, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_confirmation_path, alert: "Try again later." }

  def create
    ProfileMailer.account_confirmation(user).deliver_later if can_send_confirmation_email?
    redirect_to registration_confirmation_pending_path, notice: "If an account exists with that email, we will send you a confirmation link."
  end

  private

  def can_send_confirmation_email?
    normalized_email.present? && user.present? && user.inactive?
  end

  def user
    @user ||= User.find_by(email_address: normalized_email)
  end

  def normalized_email
    @normalized_email ||= params[:email_address].to_s.strip.downcase
  end
end
