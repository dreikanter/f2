class BadgeComponent < ViewComponent::Base
  COLOR_CLASSES = {
    neutral: "bg-surface-muted text-heading ring-muted/20",
    info: "bg-brand-subtle text-brand-strong ring-brand/20",
    success: "bg-success-subtle text-success-strong ring-success/20",
    warning: "bg-warning-subtle text-warning-strong ring-warning/20",
    danger: "bg-danger-subtle text-danger-strong ring-danger/20"
  }.freeze

  def initialize(text:, color: :neutral, key: nil)
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
      "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
      COLOR_CLASSES[@color] || COLOR_CLASSES[:neutral]
    ].join(" ")
  end

  def data_attributes
    @key ? { key: @key } : nil
  end
end
