class Admin::UserEmailStatusComponent < ViewComponent::Base
  REACTIVATE_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md bg-sky-600 px-4 py-2 text-base font-semibold text-white shadow-sm transition hover:bg-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1 cursor-pointer".freeze
  VIEW_EVENTS_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md border border-slate-200 bg-white px-4 py-2 text-base font-semibold text-slate-600 shadow-sm transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1".freeze

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
    ListComponent::StatItemComponent.new(label: label, value: value)
  end

  def status_badge
    helpers.tag.span("Deactivated", class: "inline-flex items-center rounded-md bg-amber-50 px-2 py-1 text-xs font-medium text-amber-700 ring-1 ring-inset ring-amber-600/20")
  end

  def time_value(time)
    helpers.tag.time(
      "#{time.to_date.to_fs(:long)} (#{helpers.short_time_ago(time)})",
      datetime: time.iso8601,
      title: time.to_fs(:long)
    )
  end

  def actions_value
    helpers.safe_join([
      helpers.button_to("Reactivate Email", helpers.admin_user_email_reactivation_path(@user), method: :post, class: REACTIVATE_CLASSES),
      helpers.link_to("View Email Events", helpers.admin_events_path(filter: { user_id: @user.id, type: helpers.mail_event_types }), class: VIEW_EVENTS_CLASSES)
    ], " ")
  end
end
