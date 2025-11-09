class SpinnerComponent < ViewComponent::Base
  attr_reader :css_class

  def initialize(css_class: nil)
    @css_class = css_class
  end
end
