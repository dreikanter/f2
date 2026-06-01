class Admin::UserDetailsComponent < ViewComponent::Base
  def initialize(user:, stats:)
    @user = user
    @stats = stats
  end

  def call
    render(DescriptionListComponent.new) do |list|
      list.with_item(stat_item("Email", @user.email_address))
      list.with_item(stat_item("Permissions", permissions_value))
      list.with_item(stat_item("Created", time_value(@user.created_at)))
      list.with_item(stat_item("Updated", time_value(@user.updated_at)))
      list.with_item(stat_item("Password Updated", optional_time(@user.password_updated_at)))
      list.with_item(stat_item("Last Seen", optional_time(@stats.last_session&.updated_at)))
    end
  end

  private

  def stat_item(label, value)
    ListComponent::StatItemComponent.new(label: label, value: value)
  end

  def permissions_value
    return helpers.tag.span("None", class: "text-slate-500") if @user.permissions.empty?

    @user.permissions.pluck(:name).join(", ")
  end

  def optional_time(time)
    time.present? ? time_value(time) : helpers.tag.span("Never", class: "text-slate-500")
  end

  def time_value(time)
    helpers.tag.time(
      "#{time.to_date.to_fs(:long)} (#{helpers.short_time_ago(time)})",
      datetime: time.iso8601,
      title: time.to_fs(:long)
    )
  end
end
