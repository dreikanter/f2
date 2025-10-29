class RegistrationsController < ApplicationController
  layout "tailwind"

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to registration_path(code: params[:code]), alert: "Try again later." }

  def show
    return redirect_to status_path if authenticated?
    return redirect_to root_path unless params[:code].present?

    @invite = Invite.includes(:created_by_user).find_by(id: params[:code])

    return if @invite.nil? || @invite.used?

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
      ProfileMailer.account_confirmation(@user).deliver_later
      redirect_to registration_confirmation_pending_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email_address, :password)
  end
end
