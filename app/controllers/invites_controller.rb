class InvitesController < ApplicationController
  layout "tailwind"

  def index
    authorize Invite
    @invites = ordered_invites
    @invite_stats = invite_stats
  end

  def create
    authorize Invite
    @new_invite = create_invite_if_possible
    render_invite_updates
  end

  def destroy
    invite = created_invites.find(params[:id])
    authorize invite
    invite.destroy!

    render_invite_updates
  end

  private

  def create_invite_if_possible
    new_invite = nil
    Invite.transaction do
      created_invites_count = created_invites.count
      new_invite = created_invites.create! if available_invites_count > created_invites_count
    end
    new_invite
  end

  def render_invite_updates
    invites = ordered_invites

    render turbo_stream: [
      turbo_stream.update("invites-table", partial: "invites/table", locals: { invites: invites, new_invite_id: @new_invite&.id }),
      turbo_stream.update("invite-stats", partial: "invites/stats", locals: invite_stats),
      turbo_stream.update("create-invite-button", partial: "invites/create_button", locals: {
        can_create: policy(Invite).create?
      })
    ]
  end

  def invite_stats
    {
      available_invites_count: available_invites_count,
      created_invites_count: created_invites.count,
      invited_users_count: created_invites.where.not(invited_user_id: nil).count,
      unused_invites_count: created_invites.where(invited_user_id: nil).count
    }
  end

  def available_invites_count
    Current.user.available_invites
  end

  def created_invites
    Current.user.created_invites
  end

  def ordered_invites
    policy_scope(Invite).includes(:invited_user, :created_by_user).order(created_at: :desc)
  end
end
