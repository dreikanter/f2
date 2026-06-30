class PostListItemComponent < ListItemComponent
  STATUS_DISPLAY = {
    "draft"     => { icon: "file",         color: "text-faint",  label: "Draft" },
    "enqueued"  => { icon: "clock",        color: "text-blue-500",   label: "Enqueued" },
    "rejected"  => { icon: "circle-x",     color: "text-orange-500", label: "Rejected" },
    "published" => { icon: "circle-check", color: "text-green-600",  label: "Reposted" },
    "failed"    => { icon: "circle-x",     color: "text-red-600",    label: "Failed" },
    "withdrawn" => { icon: "trash-2",      color: "text-faint",  label: "Withdrawn" }
  }.freeze

  def initialize(post:, show_feed: false)
    super()
    @post = post
    @show_feed = show_feed
  end

  def before_render
    with_icon { icon_element }
    with_primary { primary_element }
    with_secondary { secondary_element }
    with_trailing { trailing_element } if show_actions?
  end

  private

  attr_reader :post, :show_feed

  def li_id
    helpers.dom_id(post)
  end

  # Rows live inside a single bordered list, so they carry no border or shadow of
  # their own; withdrawn posts get a muted background to read as inactive.
  def row_css_class
    helpers.class_names(
      "transition duration-75",
      "bg-surface-muted hover:bg-surface-sunken" => withdrawn?,
      "hover:bg-surface-muted" => !withdrawn?
    )
  end

  def icon_element
    helpers.tag.span(status_icon, class: "inline-flex shrink-0", data: { key: "post.status-icon" })
  end

  def primary_element
    helpers.tag.div(helpers.safe_join([title_element, withdrawn_badge].compact),
                    class: "flex min-w-0 flex-1 items-baseline gap-2")
  end

  def withdrawn_badge
    render(BadgeComponent.new(text: "Withdrawn", color: :gray)) if withdrawn?
  end

  # The status sits leftmost and is always present, so every following item
  # (group, counts) leads with a middot.
  def secondary_element
    helpers.tag.div(helpers.safe_join(status_segments, helpers.middot),
                    class: "truncate text-sm text-faint")
  end

  def status_segments
    segments = [status_element]
    segments << group_segment if show_group?
    segments << helpers.tag.span(attachment_label, data: { key: "post.attachments" }) if show_attachment_count?
    segments << helpers.tag.span(comment_label, data: { key: "post.comments" }) if show_comment_count?
    segments
  end

  def status_element
    if status_url
      helpers.link_to(status_label_with_time, status_url,
                      class: "transition hover:text-body", data: { key: "post.status" })
    else
      helpers.tag.span(status_label_with_time, data: { key: "post.status" })
    end
  end

  def group_segment
    helpers.tag.span(helpers.safe_join(["Group: ", helpers.link_to(group_label, group_url, title: group_hint, class: "transition hover:text-body")]),
                     data: { key: "post.group" })
  end

  def trailing_element
    helpers.safe_join([menu, delete_modal].compact)
  end

  def menu
    render(DropdownMenuComponent.new(menu_id: menu_id, items: menu_items, width: "w-40"))
  end

  def delete_modal
    render(PostDeleteModalComponent.new(post: post)) if delete_allowed?
  end

  def menu_items
    items = [{ label: "Details", href: post_url }]
    items << { label: "Source", href: source_url, target: "_blank", rel: "noopener", data: { key: "post.source" } } if source_url
    if delete_allowed?
      items << { label: "Delete…", href: "#",
                 data: { controller: "modal-trigger", modal_trigger_modal_id_value: delete_modal_id, action: "click->modal-trigger#open" } }
    end
    items
  end

  def title
    helpers.post_content_preview(post.content, 160)
  end

  # The title links to the post page. ReadonlyPostListItemComponent overrides
  # this with plain text where those owner-scoped routes aren't reachable.
  def title_element
    helpers.link_to(title, post_url,
                    class: "truncate text-base text-heading transition hover:text-heading rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-sky-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white")
  end

  # Whether to render the actions menu (Details/Source/Delete). Disabled by
  # ReadonlyPostListItemComponent.
  def show_actions?
    true
  end

  def post_url
    helpers.post_path(post)
  end

  def group_label
    return unless show_feed
    group = post.feed&.target_group
    "@#{group}" if group.present?
  end

  def group_url
    return unless show_feed && post.feed
    helpers.feed_path(post.feed)
  end

  def group_hint
    post.feed&.display_name
  end

  def status_display
    STATUS_DISPLAY[post.status.to_s] ||
      { icon: "file", color: "text-faint", label: post.status.to_s.capitalize }
  end

  def status_icon
    helpers.icon(status_display[:icon], css_class: "size-4 #{status_display[:color]}")
  end

  def status_label_with_time
    helpers.content_tag(:span, helpers.safe_join([status_display[:label], ": ", helpers.short_time_ago_tag(status_time)]))
  end

  # The status badge reports when the post reached its current state. For a
  # published post that is the repost moment (see Post#reposted_at); for every
  # other state it is the last transition, which updated_at tracks.
  def status_time
    post.reposted_at || post.updated_at
  end

  def reposted?
    post.published?
  end

  # The target group rides alongside the status as its own labeled item
  # ("Group: @name") whenever the list spans feeds, keeping the status itself
  # uncluttered and reading the same for every status.
  def show_group?
    group_label.present?
  end

  # Attachment and comment counts describe what made it onto FreeFeed, so they
  # only make sense once the post is actually reposted.
  def show_attachment_count?
    reposted? && attachment_count.positive?
  end

  def show_comment_count?
    reposted? && comment_count.positive?
  end

  def attachment_label
    helpers.pluralize(attachment_count, "attachment")
  end

  def comment_label
    helpers.pluralize(comment_count, "comment")
  end

  def attachment_count
    Array(post.attachment_urls).size
  end

  def comment_count
    Array(post.comments).size
  end

  def source_url
    post.source_url.presence
  end

  def status_url
    helpers.feed_path(post.feed) if post.feed
  end

  def delete_allowed?
    helpers.policy(post).destroy?
  end

  def withdrawn?
    post.status.to_s == "withdrawn"
  end

  def delete_modal_id
    PostDeleteModalComponent.modal_id(post)
  end

  def menu_id
    "post-menu-#{post.id}"
  end
end
