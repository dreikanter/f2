class SmallBoxComponent < ViewComponent::Base
  renders_one :notice
  renders_one :footer

  def initialize(title:, column_classes: "col-12 col-md-8 col-lg-6")
    @title = title
    @column_classes = column_classes
  end
end
