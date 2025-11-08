class SpinnerComponent < ViewComponent::Base
  def initialize(size: "w-8 h-8", color: "text-gray-300", fill: "fill-cyan-600", css_class: nil)
    @size = size
    @color = color
    @fill = fill
    @css_class = css_class
  end

  def classes
    class_names(@size, @color, "animate-spin", @fill, @css_class)
  end
end
