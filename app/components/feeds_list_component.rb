class FeedsListComponent < ViewComponent::Base
  def initialize(feeds:)
    @feeds = feeds
  end

  CONTINUE_SETUP_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:bg-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1".freeze
  DISCARD_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-inset ring-slate-300 transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1".freeze
  DISCARD_CONFIRM = "Discard this draft? No data will be lost since it hasn't been activated.".freeze

  def call
    component = ListComponent.new

    @feeds.each do |feed|
      component.with_item(ListComponent::ItemComponent.new(
        title: display_title_for(feed),
        title_url: helpers.feed_path(feed),
        metadata_segments: metadata_segments_for(feed),
        badge: badge_for(feed),
        actions: actions_for(feed)
      ))
    end

    render(component)
  end

  private

  def display_title_for(feed)
    feed.display_name
  end

  def badge_for(feed)
    return nil unless feed.draft?

    render(BadgeComponent.new(text: "Draft", color: :gray, key: "feed.#{feed.id}.draft_badge"))
  end

  # FR-023: drafts surface inline "Continue setup" and "Discard" affordances so
  # users can act on stalled drafts without opening the show page. FR-024: the
  # discard confirmation copy is softer than the regular feed delete since
  # nothing has been published yet.
  def actions_for(feed)
    return nil unless feed.draft?

    safe_join([
      helpers.link_to("Continue setup", helpers.edit_feed_path(feed),
                      class: CONTINUE_SETUP_CLASSES,
                      data: { key: "feed.#{feed.id}.continue_setup" }),
      helpers.button_to("Discard", helpers.feed_path(feed),
                        method: :delete,
                        class: DISCARD_CLASSES,
                        data: { key: "feed.#{feed.id}.discard" },
                        form: { data: { turbo_confirm: DISCARD_CONFIRM } })
    ])
  end

  def metadata_segments_for(feed)
    [
      target_segment(feed),
      safe_join(["Refreshed:", feed.last_refreshed_at ? content_tag(:span, "#{helpers.short_time_ago(feed.last_refreshed_at)} ago", title: helpers.long_time_format(feed.last_refreshed_at)) : "Never"], " "),
      safe_join(["Publication:", feed.most_recent_post_date ? content_tag(:span, "#{helpers.short_time_ago(feed.most_recent_post_date)} ago", title: helpers.long_time_format(feed.most_recent_post_date)) : "None"], " ")
    ]
  end

  def target_segment(feed)
    target = feed.target_group.presence || "None"
    return "Target: #{target}" if target == "None" || !feed.access_token

    url = "#{feed.access_token.host}/#{feed.target_group}"
    link_content = safe_join([target, " ".html_safe, helpers.lucide_icon("external-link", size: "size-3.5", css_class: "inline align-text-bottom")])
    safe_join(["Target:", helpers.link_to(link_content, url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")], " ")
  end
end
