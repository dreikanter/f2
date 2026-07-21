class EmptyStateComponent < ViewComponent::Base
  def initialize(text = nil)
    @text = text
  end

  def call
    content_tag :div, class: "w-full rounded-lg border border-dashed border-border-strong bg-surface p-6", data: { key: "empty-state" } do
      content_tag :div, class: "space-y-6 py-12 text-center text-muted", data: { key: "empty-state.body" } do
        body
      end
    end
  end

  private

  def body
    content.presence || content_tag(:p, @text)
  end
end
