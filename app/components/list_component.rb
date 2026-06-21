class ListComponent < SlotListComponent
  # No `overflow-hidden`: it would clip row dropdown menus that open past the
  # list's bottom edge. Rows round their own first/last corners instead (see
  # ListItemComponent), so the rounded container still looks clean.
  DEFAULT_CSS_CLASSES = "rounded-lg border border-slate-200 bg-white divide-y divide-slate-200"

  private

  def container_tag
    :ul
  end
end
