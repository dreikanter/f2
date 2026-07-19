module FeedHelper
  # Plain-language label for a detection candidate. Deterministic profiles
  # show their display_name; the AI profile injects the user's input into a
  # short sentence so the chooser reads naturally for a free-form prompt.
  def candidate_summary(profile_key, input)
    case profile_key
    when "llm"
      "Follow with AI: \"#{input}\""
    else
      FeedProfile.display_name_for(profile_key)
    end
  end

  # Profile-key → source-param-key map the preview button reads to build
  # preview requests: every offered candidate while the chooser is live,
  # otherwise just the feed's own profile.
  def preview_source_keys(feed, candidates, show_chooser:)
    if show_chooser
      candidates.to_h { |candidate| [candidate.profile_key, FeedProfile.source_key_for(candidate.profile_key)] }
    else
      { feed.feed_profile_key => FeedProfile.source_key_for(feed.feed_profile_key) }
    end
  end

  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "source" unless feed.source_input.present?
    missing_parts << "name" unless feed.name.present?
    missing_parts << "feed profile" unless feed.feed_profile_present?
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts << "schedule" unless feed.cron_expression.present?
    if FeedProfile.depends_on_ai?(feed.feed_profile_key)
      missing_parts << "active AI credential" unless feed.ai_credential&.active?
      missing_parts << "AI model" unless feed.ai_model.present?
    end
    missing_parts
  end

  def feed_status_icon(feed)
    if feed.enabled?
      icon("circle-play", css_class: "size-4 text-success",
                  title: "Enabled", aria_label: "Enabled")
    elsif feed.draft?
      icon("circle-dashed", css_class: "size-4 text-muted",
                  title: "Draft", aria_label: "Draft")
    else
      # Warning rather than muted: matches the Disabled badge, and a stalled
      # feed deserves attention a draft doesn't.
      icon("circle-pause", css_class: "size-4 text-warning",
                  title: "Disabled", aria_label: "Disabled")
    end
  end

  def feed_status_badge(feed)
    case feed.state.to_sym
    when :draft    then BadgeComponent.new(text: "Draft", color: :neutral, key: "feed.#{feed.id}.draft_badge")
    when :disabled then BadgeComponent.new(text: "Disabled", color: :warning, key: "feed.#{feed.id}.disabled_badge")
    when :enabled  then BadgeComponent.new(text: "Enabled", color: :success, key: "feed.#{feed.id}.enabled_badge")
    end
  end

  # Action menu items for the feed page header. Refresh applies only to an
  # enabled feed; the destructive actions open the confirmation modals rendered
  # alongside the feed page.
  def feed_actions_menu_items(feed)
    items = []
    items << { label: "Refresh", href: feed_refresh_path(feed), method: :post, data: { key: "feed.#{feed.id}.refresh" } } if feed.enabled?
    items << { label: "Edit", href: edit_feed_path(feed), data: { key: "feed.#{feed.id}.edit" } }

    if feed.target_group.present?
      items << { label: "Purge feed…", href: "#",
                 data: { key: "feed.#{feed.id}.purge", controller: "modal-trigger",
                         modal_trigger_modal_id_value: "purge-modal-#{feed.id}", action: "click->modal-trigger#open" } }
    end
    items << { label: "Delete feed…", href: "#",
               data: { key: "feed.#{feed.id}.delete", controller: "modal-trigger",
                       modal_trigger_modal_id_value: "delete-feed-modal-#{feed.id}", action: "click->modal-trigger#open" } }

    items
  end

  def feed_summary_line(active_count:, inactive_count:, draft_count:)
    counts = { "active feed" => active_count, "inactive feed" => inactive_count, "draft feed" => draft_count }
    parts = counts.reject { |_label, count| count.zero? }
                  .map { |label, count| pluralize(count, label) }
    return nil if parts.empty?

    "You have #{parts.to_sentence}"
  end
end
