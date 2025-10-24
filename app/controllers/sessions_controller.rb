class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))

    if user
      create_session_for(user)
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end

  private

  def create_session_for(user)
    if user.suspended?
      user.sessions.destroy_all
      redirect_to new_session_path, alert: "Your account has been suspended."
    else
      start_new_session_for user
      redirect_to after_authentication_url
    end
  end
end
