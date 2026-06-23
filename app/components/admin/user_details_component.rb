class Admin::UserDetailsComponent < ViewComponent::Base
  STATUS_BADGES = {
    "inactive" => { label: "Pending confirmation", classes: "bg-amber-50 text-amber-700 ring-amber-600/20" },
    "active" => { label: "Active", classes: "bg-emerald-50 text-emerald-700 ring-emerald-600/20" },
    "suspended" => { label: "Suspended", classes: "bg-red-50 text-red-700 ring-red-600/20" }
  }.freeze

  def initialize(user:, stats:)
    @user = user
    @stats = stats
  end

  def call
    render(DescriptionListComponent.new) do |list|
      list.with_item(stat_item("Email", @user.email_address))
      list.with_item(stat_item("Status", status_badge))
      list.with_item(stat_item("Permissions", permissions_value))
      list.with_item(stat_item("Created", helpers.datetime_with_duration_tag(@user.created_at)))
      list.with_item(stat_item("Updated", helpers.datetime_with_duration_tag(@user.updated_at)))
      list.with_item(stat_item("Password Updated", optional_time(@user.password_updated_at)))
      list.with_item(stat_item("Last Seen", optional_time(@stats.last_session&.updated_at)))
    end
  end

  private

  def stat_item(label, value)
    StatListItemComponent.new(label: label, value: value)
  end

  def status_badge
    badge = STATUS_BADGES.fetch(@user.state) { { label: @user.state.humanize, classes: "bg-slate-50 text-slate-700 ring-slate-600/20" } }
    helpers.tag.span(
      badge[:label],
      class: "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset #{badge[:classes]}",
      data: { key: "user_details.status" }
    )
  end

  def permissions_value
    return helpers.tag.span("None", class: "text-slate-500") if @user.permissions.empty?

    @user.permissions.map(&:display_name).join(", ")
  end

  def optional_time(time)
    time.present? ? helpers.datetime_with_duration_tag(time) : helpers.tag.span("Never", class: "text-slate-500")
  end
end
