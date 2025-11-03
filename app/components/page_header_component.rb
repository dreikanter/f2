class PageHeaderComponent < ViewComponent::Base
  renders_many :context_paragraphs, ->(content = nil, &block) do
    content || block.call
  end
  renders_many :action_buttons, ->(content = nil, &block) do
    content || block.call
  end

  def initialize(title:)
    @title = title
  end
end
