class PageHeaderComponent < ViewComponent::Base
  renders_one :title_icon

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
end
