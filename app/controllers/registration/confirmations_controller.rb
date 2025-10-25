class Registration::ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_confirmation_path, alert: "Try again later." }

  def new
  end

  def create
    user = User.find_by(email_address: email_params[:email_address])

    if user&.inactive?
      ProfileMailer.account_confirmation(user).deliver_later
      redirect_to registration_confirmation_pending_path, notice: "Confirmation email sent. Please check your inbox."
    else
      redirect_to new_registration_confirmation_path, alert: "No inactive account found with that email address."
    end
  end

  private

  def email_params
    params.permit(:email_address)
  end
end
