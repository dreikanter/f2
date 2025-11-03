class PageHeaderComponent < ViewComponent::Base
  renders_many :context_paragraphs, ->(content = nil, &block) do
    content || block.call
  end
  renders_one :actions

  def initialize(title:)
    @title = title
  end
end
