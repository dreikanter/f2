class Admin::UserInvitationsComponent < ViewComponent::Base
  EDIT_CLASSES = "font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover text-sm".freeze

  def initialize(user:, stats:)
    @user = user
    @stats = stats
  end

  def call
    render(DescriptionListComponent.new) do |list|
      list.with_item(StatListItemComponent.new(label: "Available Invites", value: available_invites_value, key: "invitations.available_invites"))
      list.with_item(StatListItemComponent.new(label: "Created Invites", value: @stats.created_invites_count))
      list.with_item(StatListItemComponent.new(label: "Invited Users", value: invited_users_value))
    end
  end

  private

  def available_invites_value
    helpers.tag.span(class: "flex items-center gap-4") do
      helpers.safe_join([
        helpers.render(partial: "admin/users/available_invites_value", locals: { user: @user }),
        helpers.link_to("Edit", "#", class: EDIT_CLASSES, data: edit_modal_data)
      ])
    end
  end

  def invited_users_value
    links = @stats.invited_users.map { |invite| helpers.admin_user_link(invite.invited_user) }
    helpers.safe_join(links, ", ")
  end

  def edit_modal_data
    {
      controller: "modal-trigger",
      modal_trigger_modal_id_value: "edit-available-invites-modal-#{@user.id}",
      action: "click->modal-trigger#open"
    }
  end
end
