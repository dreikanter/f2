# A non-interactive PostListItemComponent: renders the post as plain text with no
# title link or actions menu. Used where the owner-scoped post routes aren't
# reachable, such as the admin feed page showing another user's posts.
class ReadonlyPostListItemComponent < PostListItemComponent
  private

  def title_element
    helpers.content_tag(:span, title, class: "truncate text-base text-slate-900")
  end

  # The owner-scoped feed route isn't reachable here, so the status stays plain
  # text rather than linking to it.
  def status_url
    nil
  end

  def show_actions?
    false
  end
end
