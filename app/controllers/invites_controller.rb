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
    Invite.transaction do
      authorize Invite
      Current.user.created_invites.create!
    end

    render_invite_updates
  end

  def destroy
    invite = Current.user.created_invites.find(params[:id])
    authorize invite
    invite.destroy!

    render_invite_updates
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
