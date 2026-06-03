class StatsBarComponent < SlotListComponent
  DEFAULT_CSS_CLASSES = "overflow-hidden md:flex md:divide-x md:divide-slate-200 rounded-lg border border-slate-200 bg-white"

  private

  def container_tag
    :dl
  end
end
