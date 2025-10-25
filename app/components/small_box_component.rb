class SmallBoxComponent < ViewComponent::Base
  renders_one :notice
  renders_one :footer

  def initialize(title:)
    @title = title
  end
end
