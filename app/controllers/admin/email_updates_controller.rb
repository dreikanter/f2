class Admin::EmailUpdatesController < ApplicationController
  def edit
    @user = User.find(params[:user_id])
    authorize @user, :update_email?
  end

  def update
    user = User.find(params[:user_id])
    authorize user, :update_email?

    return redirect_to edit_admin_user_email_update_path(user), alert: "Email address cannot be blank." if new_email.blank?
    return redirect_to edit_admin_user_email_update_path(user), alert: "New email is the same as the current email." if new_email == user.email_address
    return redirect_to edit_admin_user_email_update_path(user), alert: "Email address is already taken." if User.exists?(email_address: new_email)

    if require_confirmation?
      if user.update(unconfirmed_email: new_email)
        ProfileMailer.deliver_to(:email_change_confirmation, user)
        redirect_to admin_user_path(user), notice: "Confirmation email sent to #{new_email}. User must confirm before change takes effect."
      else
        redirect_to edit_admin_user_email_update_path(user), alert: "Failed to update email address."
      end
    elsif user.update(email_address: new_email)
      redirect_to admin_user_path(user), success: "Email address updated."
    else
      redirect_to edit_admin_user_email_update_path(user), alert: "Failed to update email address."
    end
  end

  private

  def new_email
    @new_email ||= params.dig(:user, :email_address)
  end

  def require_confirmation?
    params[:require_confirmation] == "1"
  end
end
