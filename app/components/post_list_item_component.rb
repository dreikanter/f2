class PostListItemComponent < ViewComponent::Base
  STATUS_DISPLAY = {
    "draft"     => { icon: "file",         color: "text-slate-400",  label: "Draft" },
    "enqueued"  => { icon: "clock",        color: "text-blue-500",   label: "Enqueued" },
    "rejected"  => { icon: "circle-x",     color: "text-orange-500", label: "Rejected" },
    "published" => { icon: "circle-check", color: "text-green-600",  label: "Reposted" },
    "failed"    => { icon: "circle-x",     color: "text-red-600",    label: "Failed" },
    "withdrawn" => { icon: "trash-2",      color: "text-slate-400",  label: "Withdrawn" }
  }.freeze

  def initialize(post:, show_feed: false)
    @post = post
    @show_feed = show_feed
  end

  private

  attr_reader :post, :show_feed

  def title
    helpers.post_content_preview(post.content, 160)
  end

  # The title links to the post page. ReadonlyPostListItemComponent overrides this
  # with plain text where those owner-scoped routes aren't reachable.
  def title_element
    helpers.link_to(title, post_url,
                    class: "truncate text-base text-slate-900 transition hover:text-slate-700 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-sky-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white")
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
      { icon: "file", color: "text-slate-400", label: post.status.to_s.capitalize }
  end

  def status_icon
    helpers.icon(status_display[:icon], css_class: "size-4 #{status_display[:color]}")
  end

  # Group the label, parens and the time tag inside a single inline wrapper so
  # the surrounding flex gap only spaces the icon from the text. Without the
  # wrapper the parens become separate flex items and the duration drifts away
  # from them, e.g. "Reposted ( 1d )" instead of "Reposted (1d)".
  def status_label_with_time
    helpers.content_tag(:span, helpers.safe_join([status_display[:label], " (", helpers.short_time_ago_tag(status_time), ")"]))
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

  def freefeed_url
    post.freefeed_url
  end

  def status_links_to_freefeed?
    reposted? && freefeed_url.present?
  end

  def delete_allowed?
    helpers.policy(post).destroy?
  end

  def withdrawn?
    post.status.to_s == "withdrawn"
  end

  # Rows live inside a single bordered list, so they carry no border or shadow of
  # their own; withdrawn posts get a muted background to read as inactive.
  def row_classes
    helpers.class_names(
      "px-5 py-3 transition duration-75",
      "bg-slate-50 hover:bg-slate-100" => withdrawn?,
      "hover:bg-slate-50" => !withdrawn?
    )
  end

  def delete_modal_id
    PostDeleteModalComponent.modal_id(post)
  end

  def menu_id
    "post-menu-#{post.id}"
  end
end
