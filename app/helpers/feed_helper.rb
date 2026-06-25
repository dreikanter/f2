module FeedHelper
  # How a candidate's self-test verdict reads in the chooser: a short badge and
  # an optional advisory line. Selectability is the candidate's own concern
  # (see Candidate#failed?), so it isn't carried here.
  CandidateStatus = Data.define(:label, :color, :note)

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

  # Presentation for a candidate's self-test verdict. Returns nil when the
  # candidate carries no verdict (nothing to show).
  def candidate_status(candidate)
    if candidate.passed?
      note = "No posts yet — we'll pick up new ones as they're published." if candidate.posts_found.zero?
      CandidateStatus.new(label: "Tested", color: :green, note: note)
    elsif candidate.unreachable?
      CandidateStatus.new(
        label: "Couldn't reach",
        color: :yellow,
        note: "We couldn't reach the source just now. Pick this only if you think it's temporary."
      )
    elsif candidate.failed?
      CandidateStatus.new(
        label: "Won't work",
        color: :red,
        note: "We tried, but couldn't read any posts from this source."
      )
    elsif candidate.not_tested?
      CandidateStatus.new(label: "Not tested", color: :gray, note: nil)
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
    missing_parts
  end

  def feed_status_icon(feed)
    if feed.enabled?
      icon("circle-play", css_class: "size-4 text-emerald-500",
                  title: "Enabled", aria_label: "Enabled")
    elsif feed.draft?
      icon("circle-dashed", css_class: "size-4 text-slate-400",
                  title: "Draft", aria_label: "Draft")
    else
      icon("circle-pause", css_class: "size-4 text-slate-400",
                  title: "Disabled", aria_label: "Disabled")
    end
  end

  def feed_status_badge(feed)
    case feed.state.to_sym
    when :draft    then BadgeComponent.new(text: "Draft", color: :gray, key: "feed.#{feed.id}.draft_badge")
    when :disabled then BadgeComponent.new(text: "Disabled", color: :yellow, key: "feed.#{feed.id}.disabled_badge")
    when :enabled  then BadgeComponent.new(text: "Enabled", color: :green, key: "feed.#{feed.id}.enabled_badge")
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
