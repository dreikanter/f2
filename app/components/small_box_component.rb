class SmallBoxComponent < ViewComponent::Base
  renders_one :notice
  renders_one :footer

  def initialize(title:, max_width: "28rem")
    @title = title
    @max_width = max_width
  end
end
