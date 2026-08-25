class StatsBarComponent < SlotListComponent
  DEFAULT_CSS_CLASSES = "overflow-hidden md:flex md:divide-x md:divide-border rounded-lg border border-border bg-surface"

  private

  # Activates the hover tooltips that stat items declare.
  def default_data
    { controller: "tooltips" }
  end

  def container_tag
    :dl
  end
end
