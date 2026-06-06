module FeedHelper
  # Plain-language label for a detection candidate. URL-based candidates
  # use the profile's display_name; query candidates inject the
  # user's input into a short sentence so the chooser feels natural for
  # non-URL inputs.
  def candidate_summary(profile_key, input)
    case profile_key
    when "llm_web_search"
      "Follow AI search results for \"#{input}\""
    else
      FeedProfile.display_name_for(profile_key)
    end
  end

  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "source" unless feed.source_input.present?
    missing_parts << "feed profile" unless feed.feed_profile_present?
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts << "schedule" unless feed.cron_expression.present?
    missing_parts
  end

  def feed_status_icon(feed)
    if feed.enabled?
      icon("circle-check", css_class: "size-4 text-emerald-500",
                  title: "Enabled", aria_label: "Enabled")
    elsif feed.draft?
      icon("square-pen", css_class: "size-4 text-amber-500",
                  title: "Draft", aria_label: "Draft")
    else
      icon("circle-x", css_class: "size-4 text-slate-400",
                  title: "Disabled", aria_label: "Disabled")
    end
  end

  def feed_status_badge(feed)
    case feed.state.to_sym
    when :draft    then BadgeComponent.new(text: "Draft", color: :gray, key: "feed.#{feed.id}.draft_badge")
    when :disabled then BadgeComponent.new(text: "Disabled", color: :yellow, key: "feed.#{feed.id}.disabled_badge")
    when :enabled  then BadgeComponent.new(text: "Active", color: :green, key: "feed.#{feed.id}.enabled_badge")
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
