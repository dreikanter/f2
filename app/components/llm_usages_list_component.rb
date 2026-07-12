class LlmUsagesListComponent < ListComponent
  def initialize(usages:)
    super()
    @usages = usages
  end

  def before_render
    @usages.each { |usage| with_item(LlmUsageListItemComponent.new(usage: usage)) }
  end
end
