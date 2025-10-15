class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to registration_path(code: params[:code]), alert: "Try again later." }

  def show
    return redirect_to status_path if authenticated?
    return redirect_to root_path unless params[:code].present?

    @invite = Invite.includes(:created_by_user).find_by(id: params[:code])

    return redirect_to root_path if @invite.nil?
    return if @invite.used?

    @user = User.new
  end

  def create
    return redirect_to status_path if authenticated?
    return redirect_to root_path unless params[:code].present?

    @invite = Invite.find_by(id: params[:code])

    return redirect_to root_path if @invite.nil? || @invite.used?

    @user = User.new(user_params)

    if @user.save
      @invite.update!(invited_user: @user)
      @user.create_onboarding!
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome! Your account has been created."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  end
end
