class Admin::UserEmailStatusComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  def call
    render(DescriptionListComponent.new) do |list|
      list.with_item(stat_item("Status", status_badge))
      list.with_item(stat_item("Deactivated At", time_value(@user.email_deactivated_at)))
      list.with_item(stat_item("Reason", @user.email_deactivation_reason.humanize))
      list.with_item(stat_item("Actions", actions_value))
    end
  end

  private

  def stat_item(label, value)
    StatListItemComponent.new(label: label, value: value)
  end

  def status_badge
    render(BadgeComponent.new(text: "Deactivated", color: :warning))
  end

  def time_value(time)
    helpers.datetime_with_duration_tag(time)
  end

  def actions_value
    helpers.safe_join([
      helpers.button_to("Reactivate Email", helpers.admin_user_email_reactivation_path(@user), method: :post,
                        class: class_names(helpers.primary_button_classes(compact: true), "cursor-pointer disabled:cursor-not-allowed disabled:opacity-50")),
      helpers.link_to("View Email Events", helpers.admin_events_path(filter: { user_id: @user.id, type: helpers.mail_event_types }),
                      class: helpers.secondary_button_classes(compact: true))
    ], " ")
  end
end
