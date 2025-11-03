class PageHeaderComponent < ViewComponent::Base
  renders_one :context
  renders_one :actions

  def initialize(title:)
    @title = title
  end
end
