class InvitesController < ApplicationController
  def index
    authorize Invite
    @invites = policy_scope(Invite).includes(:invited_user).order(created_at: :desc)
    @available_invites_count = Current.user.available_invites
    @created_invites_count = @invites.count
    @invited_users_count = @invites.where.not(invited_user_id: nil).count
    @unused_invites_count = @invites.where(invited_user_id: nil).count
  end

  def create
    invite = nil

    Invite.transaction do
      authorize Invite
      invite = Current.user.created_invites.create!
    end

    respond_to do |format|
      format.turbo_stream { render_invite_updates }
      format.html { redirect_to invites_path, notice: "Invite created successfully." }
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to invites_path, alert: "Failed to create invite."
  end

  def destroy
    invite = Current.user.created_invites.find(params[:id])
    authorize invite
    invite.destroy!

    respond_to do |format|
      format.turbo_stream { render_invite_updates }
      format.html { redirect_to invites_path, notice: "Invite deleted successfully." }
    end
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to invites_path, alert: "Failed to delete invite."
  end

  private

  def render_invite_updates
    invites = policy_scope(Invite).includes(:invited_user).order(created_at: :desc)
    unused_count = invites.where(invited_user_id: nil).count

    render turbo_stream: [
      turbo_stream.update("invites-table", partial: "invites/table", locals: { invites: invites }),
      turbo_stream.update("invite-stats", partial: "invites/stats", locals: {
        available_invites_count: Current.user.available_invites,
        created_invites_count: invites.count,
        invited_users_count: invites.where.not(invited_user_id: nil).count,
        unused_invites_count: unused_count
      }),
      turbo_stream.update("create-invite-button", partial: "invites/create_button", locals: {
        can_create: policy(Invite).create?
      })
    ]
  end
end
