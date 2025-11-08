class ListGroupComponent::AccessTokenItemComponent < ViewComponent::Base
  include ApplicationHelper
  include TimeHelper

  def initialize(access_token:, key: nil)
    @access_token = access_token
    @key = key
  end

  private

  def status_icon
    case @access_token.status
    when "active"
      icon("check-circle", css_class: "h-5 w-5 text-emerald-600", aria_label: "Active")
    when "inactive"
      icon("x-circle", css_class: "h-5 w-5 text-slate-400", aria_label: "Inactive")
    when "pending", "validating"
      icon("clock", css_class: "h-5 w-5 text-slate-400", aria_label: @access_token.status.capitalize)
    end
  end

  def username_with_host
    owner = @access_token.owner.presence || "—"
    host = URI.parse(@access_token.host).host
    "#{owner}@#{host}"
  end

  def created_ago
    short_time_ago(@access_token.created_at)
  end

  def last_used_text
    if @access_token.last_used_at
      short_time_ago(@access_token.last_used_at)
    else
      "Never"
    end
  end
end
