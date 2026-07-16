class FeedListItemComponent < ListItemComponent
  DISCARD_CONFIRM = "Discard this draft? No data will be lost since it hasn't been activated.".freeze
  ENABLE_CONFIRM = "Enable this feed?".freeze
  DISABLE_CONFIRM = "Disable this feed?".freeze

  def initialize(feed:, admin: false)
    super()
    @feed = feed
    @admin = admin
  end

  def before_render
    with_icon { icon_element }
    with_primary { primary_element }
    with_secondary { secondary_element }
    with_trailing { menu }
  end

  private

  attr_reader :feed, :admin

  def li_id
    helpers.dom_id(feed)
  end

  def row_css_class
    HOVER_ROW_CSS_CLASS
  end

  def icon_element
    helpers.tag.span(status_icon, class: "inline-flex shrink-0", data: { key: "feed.#{feed.id}.status_icon" })
  end

  def primary_element
    helpers.tag.div(helpers.safe_join([title_link, group_element].compact),
                    class: "flex min-w-0 flex-1 items-baseline gap-2")
  end

  def secondary_element
    helpers.tag.div(helpers.safe_join(meta_segments, helpers.middot),
                    class: "truncate text-sm text-muted")
  end

  def title_link
    helpers.link_to(title, feed_url,
                    class: "truncate text-base text-heading transition hover:text-heading rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-white")
  end

  def group_element
    return unless target_group_label

    if target_group_url
      helpers.link_to(target_group_label, target_group_url, target: "_blank", rel: "noopener",
                      class: "truncate text-sm text-muted transition hover:text-body")
    else
      helpers.tag.span(target_group_label, class: "truncate text-sm text-muted")
    end
  end

  def meta_segments
    segments = [status_segment]

    # Drafts have never run, so their activity times and counts are meaningless.
    unless draft?
      segments << helpers.tag.span(helpers.safe_join(["Latest updated: ", last_refreshed_tag]), data: { key: "feed.#{feed.id}.last_refreshed" })
      segments << helpers.tag.span(helpers.safe_join(["Latest post: ", most_recent_post_tag]), data: { key: "feed.#{feed.id}.most_recent_post" })
      segments << helpers.tag.span(helpers.safe_join(["Posts: ", published_posts_count_tag]), data: { key: "feed.#{feed.id}.published_posts_count" })
    end

    segments << owner_segment if owner
    segments
  end

  def status_segment
    helpers.tag.span(status_label, data: { key: "feed.#{feed.id}.status" })
  end

  def status_label
    feed.state.capitalize
  end

  def owner_segment
    helpers.tag.span(helpers.safe_join(["Owner: ", helpers.link_to(owner.email_address, owner_url, class: "transition hover:text-body")]),
                     data: { key: "feed.#{feed.id}.owner" })
  end

  def menu
    render(DropdownMenuComponent.new(menu_id: menu_id, items: menu_items, width: "w-44"))
  end

  def menu_items
    items = []

    # An incomplete draft leads with "Continue setup" and drops "Details" —
    # there's nothing worth showing on the feed page until it has run.
    if continue_setup?
      items << { label: "Continue setup", href: edit_url, data: { key: "feed.#{feed.id}.continue_setup" } }
    else
      items << { label: "Details", href: feed_url, data: { key: "feed.#{feed.id}.details" } }
    end

    if management_actions?
      items << { label: "Edit", href: edit_url, data: { key: "feed.#{feed.id}.edit" } } unless draft?

      # A ready draft can be enabled straight from the list, same as a paused feed.
      if enabled?
        items << { label: "Disable", href: status_url, method: :patch, params: { status: "disabled" },
                   data: { key: "feed.#{feed.id}.disable", turbo_confirm: DISABLE_CONFIRM } }
      elsif can_be_enabled?
        items << { label: "Enable", href: status_url, method: :patch, params: { status: "enabled" },
                   data: { key: "feed.#{feed.id}.enable", turbo_confirm: ENABLE_CONFIRM } }
      end

      items << { label: "Discard…", href: feed_url, data: { key: "feed.#{feed.id}.discard", turbo_method: :delete, turbo_confirm: DISCARD_CONFIRM } } if draft?
    end

    items
  end

  def title
    feed.display_name
  end

  # The admin list points at the operator-facing feed page so admins can open
  # any user's feed; the regular list stays in the user's own namespace.
  def feed_url
    admin ? helpers.admin_feed_path(feed) : helpers.feed_path(feed)
  end

  def edit_url
    helpers.edit_feed_path(feed)
  end

  def status_url
    helpers.feed_status_path(feed)
  end

  def draft?
    feed.draft?
  end

  def enabled?
    feed.enabled?
  end

  def can_be_enabled?
    feed.can_be_enabled?
  end

  # The admin list spans every user's feeds, where the management actions
  # (edit, enable/disable, discard) don't apply, so only the read-only links
  # are offered there.
  def management_actions?
    !admin
  end

  # A draft still being set up leads with "Continue setup" instead of "Details".
  def continue_setup?
    management_actions? && draft?
  end

  def status_icon
    helpers.feed_status_icon(feed)
  end

  def menu_id
    "feed-menu-#{feed.id}"
  end

  def target_group_label
    "@#{feed.target_group}" if feed.target_group.present?
  end

  def target_group_url
    feed.target_group_url
  end

  def owner
    feed.user if admin
  end

  def owner_url
    helpers.admin_user_path(owner) if owner
  end

  def last_refreshed_tag
    refreshed_at = listing_last_refreshed_at
    return "Never" unless refreshed_at

    helpers.short_time_ago_tag(refreshed_at)
  end

  def most_recent_post_tag
    published_at = listing_most_recent_post_date
    return "None" unless published_at

    helpers.short_time_ago_tag(published_at)
  end

  def listing_last_refreshed_at
    return feed[:listing_last_refreshed_at] if feed.has_attribute?(:listing_last_refreshed_at)

    feed.last_refreshed_at
  end

  def listing_most_recent_post_date
    return feed[:listing_most_recent_post_date] if feed.has_attribute?(:listing_most_recent_post_date)

    feed.most_recent_post_date
  end

  def published_posts_count_tag
    helpers.number_with_delimiter(feed.published_posts_count)
  end
end
