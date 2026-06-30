class EmptyStateComponent < ViewComponent::Base
  def initialize(text = nil)
    @text = text
  end

  def call
    content_tag :div, class: "w-full rounded-none border border-dashed border-border-strong bg-surface p-0 shadow-none sm:rounded-lg sm:p-6", data: { key: "empty-state" } do
      content_tag :div, class: "space-y-6 text-center py-12", data: { key: "empty-state.body" } do
        body
      end
    end
  end

  private

  def body
    content.presence || content_tag(:p, @text, class: "text-muted")
  end
end
