class ListComponent < SlotListComponent
  DEFAULT_CSS_CLASSES = "overflow-hidden rounded-lg border border-slate-200 bg-white divide-y divide-slate-200"

  private

  def container_tag
    :ul
  end
end
