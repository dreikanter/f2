module FeedHelper
  # Plain-language label for a detection candidate. URL-based candidates
  # use the profile's display_name; handle / query candidates inject the
  # user's input into a short sentence so the chooser feels natural for
  # non-URL inputs.
  def candidate_summary(profile_key, input)
    case profile_key
    when "llm_handle_search"
      "Follow #{input} via AI search"
    when "llm_web_search"
      "Follow web search results for \"#{input}\""
    else
      FeedProfile.display_name_for(profile_key)
    end
  end

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
    elsif feed.draft?
      icon("pencil-square",
           css_class: "text-amber-500 text-base leading-5",
           title: "Draft",
           aria_label: "Draft")
    else
      icon("x-circle",
           css_class: "text-slate-400 text-base leading-5",
           title: "Disabled",
           aria_label: "Disabled")
    end
  end

  def feed_status_summary(feed)
    missing_parts = feed_missing_enablement_parts(feed)

    if feed.enabled?
      "This feed is enabled and will continue to import items on its schedule."
    elsif feed.can_be_enabled?
      "This feed is ready to enable. Turn it on to start importing posts."
    elsif missing_parts.any?
      "This feed is currently disabled. Add #{missing_parts.to_sentence} to finish setup."
    else
      "This feed is currently disabled."
    end
  end

  def feed_summary_line(active_count:, inactive_count:, draft_count:)
    active_part = pluralize_count(active_count, "active feed")
    inactive_part = pluralize_count(inactive_count, "inactive feed")
    draft_part = pluralize_count(draft_count, "draft feed")

    parts = [active_part, inactive_part, draft_part].compact
    return nil if parts.empty?

    "You have #{parts.to_sentence}"
  end

  private

  def pluralize_count(count, label)
    return nil if count.zero?

    noun = label.split.last
    base = label.remove(/\sfeed\z/)
    "#{count} #{base} #{noun.pluralize(count)}"
  end
end
