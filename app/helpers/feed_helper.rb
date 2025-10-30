module FeedHelper
  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "URL" unless feed.url.present?
    missing_parts << "feed profile" unless feed.feed_profile_present?
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts << "schedule" unless feed.cron_expression.present?
    missing_parts
  end

  def feed_status_icon(feed)
    if feed.enabled?
      icon("check-circle-fill",
           css_class: "text-emerald-500 text-base leading-5",
           title: "Enabled",
           aria_label: "Enabled")
    else
      icon("x-circle",
           css_class: "text-slate-400 text-base leading-5",
           title: "Disabled",
           aria_label: "Disabled")
    end
  end

  def feed_summary_line(active_count:, inactive_count:)
    active_part = pluralize_count(active_count, "active feed")
    inactive_part = pluralize_count(inactive_count, "inactive feed")

    parts = [active_part, inactive_part].compact
    return nil if parts.empty?

    if parts.size == 1
      "You have #{parts.first}"
    else
      "You have #{parts.first} and #{parts.last}"
    end
  end

  private

  def pluralize_count(count, label)
    return nil if count.zero?

    noun = label.split.last
    base = label.remove(/\sfeed\z/)
    "#{count} #{base} #{noun.pluralize(count)}"
  end
end
