class PostCommentsComponent < ViewComponent::Base
  CARD_CLASSES = "overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm p-4".freeze

  def initialize(post:)
    @post = post
  end

  def render?
    @post.comments.present?
  end

  def call
    content_tag(:div, class: CARD_CLASSES, data: { key: "post.comments" }) do
      safe_join([
        content_tag(:h2, "Comments (#{@post.comments.length})", class: "text-lg font-semibold text-slate-900 mb-3"),
        comments_html
      ])
    end
  end

  private

  def comments_html
    safe_join(
      @post.comments.map do |comment|
        content_tag(:div, helpers.simple_format(comment), class: "border-l-4 border-slate-300 pl-3 mb-3 last:mb-0")
      end
    )
  end
end
