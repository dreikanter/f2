class StatsBarComponent < SlotListComponent
  DEFAULT_CSS_CLASSES = "overflow-hidden md:flex md:divide-x md:divide-border rounded-lg border border-border bg-surface"

  private

  def container_tag
    :dl
  end
end
