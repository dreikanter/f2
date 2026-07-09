class Admin::UserDetailsComponent < ViewComponent::Base
  STATUS_BADGES = {
    "inactive" => { label: "Pending confirmation", color: :warning },
    "active" => { label: "Active", color: :success },
    "suspended" => { label: "Suspended", color: :danger }
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
    badge = STATUS_BADGES.fetch(@user.state) { { label: @user.state.humanize, color: :neutral } }
    render(BadgeComponent.new(text: badge[:label], color: badge[:color], key: "user_details.status"))
  end

  def permissions_value
    return helpers.tag.span("None", class: "text-muted") if @user.permissions.empty?

    @user.permissions.map(&:display_name).join(", ")
  end

  def optional_time(time)
    time.present? ? helpers.datetime_with_duration_tag(time) : helpers.tag.span("Never", class: "text-muted")
  end
end
