class Registration::ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_confirmation_path, alert: "Try again later." }

  def create
    normalized_email = params[:email_address]&.strip&.downcase

    if normalized_email.present?
      user = User.find_by(email_address: normalized_email)

      if user&.inactive?
        ProfileMailer.account_confirmation(user).deliver_later
      end
    end

    redirect_to registration_confirmation_pending_path, notice: "If an inactive account exists with that email, a confirmation link has been sent."
  end
end
