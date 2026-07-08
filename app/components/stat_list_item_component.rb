class StatListItemComponent < StatItemComponent
  DEFAULT_ITEM_CLASS = "flex items-baseline justify-between gap-4 p-4"
  LABEL_CLASSES      = "text-base text-heading whitespace-nowrap"
  # min-w-0 lets the value cell shrink inside the flex row so long values
  # (URLs, UIDs) can be ellipsized by a truncate child instead of overflowing.
  VALUE_CLASSES      = "text-base min-w-0"
end
