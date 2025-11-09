class EmptyStateComponent < ViewComponent::Base
  def call
    content_tag :div, class: "ff-card border-dashed border-slate-300 shadow-none", data: { key: "empty-state" } do
      content_tag :div, class: "ff-card__body text-center py-12", data: { key: "empty-state.body" } do
        content
      end
    end
  end
end
