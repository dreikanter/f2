class EmptyStateComponent < ViewComponent::Base
  def call
    content_tag :div, class: "ff-card border-dashed border-slate-300 shadow-none" do
      content_tag :div, class: "ff-card__body text-center py-12" do
        content
      end
    end
  end
end
