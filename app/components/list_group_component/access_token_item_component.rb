class ListGroupComponent::AccessTokenItemComponent < ViewComponent::Base
  include ApplicationHelper
  include TimeHelper

  UNKNOWN_USER = "...".freeze

  def initialize(access_token:, key: nil)
    @access_token = access_token
    @key = key
  end

  private

  def status_icon
    case @access_token.status
    when "active"
      icon("check-circle", css_class: "ff-icon-success", aria_label: "Active")
    when "inactive"
      icon("x-circle", css_class: "ff-icon-secondary", aria_label: "Inactive")
    when "pending", "validating"
      icon("clock", css_class: "ff-icon-secondary", aria_label: @access_token.status.capitalize)
    else
      icon("question-circle", css_class: "ff-icon-secondary", aria_label: "Unknown status")
    end
  end

  def username_with_host
    raise "AccessToken should be valid at this point" unless @access_token.valid?

    if @access_token.owner.present?
      "#{@access_token.owner}@#{@access_token.host_domain}"
    else
      "Host: #{@access_token.host_domain}"
    end
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
