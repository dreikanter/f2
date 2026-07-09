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

  # Compacting before joining keeps the h1 text free of stray leading
  # whitespace when there is no icon; the single-space separator keeps a
  # text-node icon readable while flex layout ignores it for element icons.
  def title_content
    safe_join([title_icon, @title].compact, " ")
  end
end
