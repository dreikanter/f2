class StatListItemComponent < StatItemComponent
  DEFAULT_ITEM_CLASS = "flex items-baseline justify-between gap-x-4 p-4"
  LABEL_CLASSES      = "shrink-0 whitespace-nowrap text-base text-heading"
  VALUE_CLASSES      = "ml-auto min-w-0 break-words text-right text-base"

  # Description list values stay on the label's line, cropping when needed.
  # Callers with genuinely multiline content can opt out of truncation.
  def initialize(label:, value:, key: nil, muted: false, truncate: true, tooltip: nil)
    super
  end
end
