class BadgeComponent < ViewComponent::Base
  COLOR_CLASSES = {
    blue: "bg-blue-100 text-blue-800",
    gray: "bg-gray-100 text-gray-800",
    red: "bg-red-100 text-red-800",
    green: "bg-green-100 text-green-800",
    yellow: "bg-yellow-100 text-yellow-800",
    orange: "bg-orange-100 text-orange-800",
    indigo: "bg-indigo-100 text-indigo-800",
    purple: "bg-purple-100 text-purple-800",
    pink: "bg-pink-100 text-pink-800"
  }.freeze

  def initialize(text:, color: :blue, key: nil)
    @text = text
    @color = color
    @key = key
  end

  def call
    content_tag(:span, @text, class: badge_classes, data: data_attributes)
  end

  private

  def badge_classes
    [
      "text-xs font-medium px-2.5 py-0.5 rounded",
      COLOR_CLASSES[@color] || COLOR_CLASSES[:blue]
    ].join(" ")
  end

  def data_attributes
    @key ? { key: @key } : nil
  end
end
