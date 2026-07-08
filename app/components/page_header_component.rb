class PageHeaderComponent < ViewComponent::Base
  renders_one :title_icon

  renders_one :breadcrumb, ->(label:, url:) do
    link_to label, url, class: "text-muted hover:text-heading transition-colors"
  end

  renders_many :context_paragraphs, ->(content = nil, &block) do
    content || block.call
  end

  renders_many :action_buttons, ->(content = nil, &block) do
    content || block.call
  end

  def initialize(title:, title_data: nil)
    @title = title
    @title_data = title_data
  end

  private

  # Joined without whitespace so the h1 text has no stray leading/trailing
  # spaces; the flex gap handles icon spacing.
  def title_content
    safe_join([title_icon, @title].compact)
  end
end
