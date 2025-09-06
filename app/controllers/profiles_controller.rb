class ProfilesController < ApplicationController
  before_action :set_user

  def show
  end

  def update
    case params[:commit]
    when "Update Email"
      update_email
    when "Change Password"
      update_password
    else
      redirect_to profile_path, alert: "Invalid action."
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def update_email
    new_email = params[:user][:email_address]

    if new_email.present? && new_email != @user.email_address
      if User.exists?(email_address: new_email)
        redirect_to profile_path, alert: "Email address is already taken."
      else
        # Store pending email change
        session[:pending_email] = new_email
        ProfileMailer.email_change_confirmation(@user, new_email).deliver_later
        redirect_to profile_path, notice: "Email confirmation sent to #{new_email}. Please check your email."
      end
    else
      redirect_to profile_path, alert: "Please enter a valid new email address."
    end
  end

  def update_password
    if @user.authenticate(params[:user][:current_password])
      if @user.update(password_params)
        redirect_to profile_path, notice: "Password updated successfully."
      else
        redirect_to profile_path, alert: @user.errors.full_messages.join(", ")
      end
    else
      redirect_to profile_path, alert: "Current password is incorrect."
    end
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
