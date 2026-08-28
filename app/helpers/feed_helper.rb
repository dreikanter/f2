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

  # The group name outlives its access token: deleting a token clears the
  # feed's token but keeps the group. Without a token there is no host to
  # build a link from, so the label falls back to the bare group name.
  def feed_target_group_link(feed)
    return if feed.target_group.blank?

    url = feed.target_group_url
    return feed.target_group unless url

    link_to "#{feed.access_token.host_domain}/#{feed.target_group}", url,
            class: "text-brand underline underline-offset-4 transition hover:text-brand-hover",
            target: "_blank", rel: "noopener"
  end

  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "source" unless feed.sourceless? || feed.source_input.present?
    missing_parts << "name" unless feed.name.present?
    missing_parts << "feed profile" unless feed.feed_profile_present?
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts << "schedule" if feed.scheduled? && feed.cron_expression.blank?
    if FeedProfile.depends_on_ai?(feed.feed_profile_key)
      missing_parts << "active AI credential" unless feed.ai_credential&.active?
      missing_parts << "active search credential" unless feed.search_credential&.active?
      missing_parts << "AI model" unless feed.ai_model.present?
    end
    missing_parts
  end

  # Names what's actually missing: "Complete setup" misleads when setup was
  # finished and a piece (like the access token) stopped working later.
  def feed_enable_hint(feed)
    missing_parts = feed_missing_enablement_parts(feed)
    return "Complete setup to enable this feed" if missing_parts.empty?

    "To enable this feed, add: #{missing_parts.to_sentence}."
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
  # enabled feed that actually pulls from a source; the destructive actions
  # open the confirmation modals rendered alongside the feed page, each behind
  # a separator so a stray click doesn't land on one.
  def feed_actions_menu_items(feed)
    items = []
    items << { label: "Refresh", href: feed_refresh_path(feed), method: :post, data: { key: "feed.#{feed.id}.refresh" } } if feed.enabled? && feed.scheduled?
    items << { label: "Edit", href: edit_feed_path(feed), data: { key: "feed.#{feed.id}.edit" } }

    if feed.target_group.present?
      items << { separator: true }
      items << { label: "Purge feed…", href: "#",
                 data: { key: "feed.#{feed.id}.purge", controller: "modal-trigger",
                         modal_trigger_modal_id_value: "purge-modal-#{feed.id}", action: "click->modal-trigger#open" } }
    end
    items << { separator: true }
    items << { label: "Delete feed…", href: "#",
               data: { key: "feed.#{feed.id}.delete", controller: "modal-trigger",
                       modal_trigger_modal_id_value: "delete-feed-modal-#{feed.id}", action: "click->modal-trigger#open" } }

    items
  end

  # Copy-paste request for the webhook endpoint panel, showing the smallest
  # payload that gets a post published.
  def webhook_curl_example(url, token)
    <<~CURL.chomp
      curl --request POST #{url} \\
        --header "Authorization: Bearer #{token}" \\
        --header "Content-Type: application/json" \\
        --data '{"content":"Hello world"}'
    CURL
  end

  def feed_summary_line(active_count:, inactive_count:, draft_count:)
    counts = { "active feed" => active_count, "inactive feed" => inactive_count, "draft feed" => draft_count }
    parts = counts.reject { |_label, count| count.zero? }
                  .map { |label, count| pluralize(count, label) }
    return nil if parts.empty?

    "You have #{parts.to_sentence}"
  end
end
