module EventsHelper
  def level_badge_class(level)
    case level.to_s
    when "debug"
      "secondary"
    when "info"
      "primary"
    when "warning"
      "warning"
    when "error"
      "danger"
    else
      "secondary"
    end
  end
end
