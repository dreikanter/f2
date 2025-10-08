class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path(code: params[:code]), alert: "Try again later." }

  def new
    return redirect_to root_path unless params[:code].present?

    @invite = Invite.find_by(id: params[:code])

    return redirect_to root_path if @invite.nil?

    if @invite.used?
      @used_invite = true
      return
    end

    return redirect_to dashboard_path if authenticated?

    @user = User.new
  end

  def create
    return redirect_to dashboard_path if authenticated?
    return redirect_to root_path unless params[:code].present?

    @invite = Invite.find_by(id: params[:code])

    return redirect_to root_path if @invite.nil? || @invite.used?

    @user = User.new(user_params)

    if @user.save
      @invite.update!(invited_user: @user)
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome! Your account has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  end
end
