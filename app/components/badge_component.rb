class BadgeComponent < ViewComponent::Base
  COLOR_CLASSES = {
    neutral: "bg-surface-muted text-heading ring-muted/20",
    info: "bg-brand-subtle text-brand-strong ring-brand/20",
    success: "bg-success-subtle text-success-strong ring-success/20",
    warning: "bg-warning-subtle text-warning-strong ring-warning/20",
    danger: "bg-danger-subtle text-danger-strong ring-danger/20",
    candy: "bg-candy-subtle text-candy-strong ring-candy/20",
    beta: "bg-beta-subtle text-beta-strong ring-beta/20"
  }.freeze

  SIZE_CLASSES = {
    default: "rounded-md px-2 py-1 text-xs",
    # Fits inside a text-base line box, so the badge can sit in a row of text
    # without pushing the line taller.
    sm: "rounded px-1.5 py-0.5 text-xs"
  }.freeze

  def initialize(text:, color: :neutral, size: :default, key: nil, data: {})
    @text = text
    @color = color
    @size = size
    @key = key
    @data = data
  end

  def call
    content_tag(:span, @text, class: badge_classes, data: data_attributes)
  end

  private

  def badge_classes
    [
      "inline-flex items-center font-medium ring-1 ring-inset",
      SIZE_CLASSES[@size] || SIZE_CLASSES[:default],
      COLOR_CLASSES[@color] || COLOR_CLASSES[:neutral]
    ].join(" ")
  end

  def data_attributes
    attributes = @data.dup
    attributes[:key] = @key if @key
    attributes.presence
  end
end
