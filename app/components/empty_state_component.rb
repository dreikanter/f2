class EmptyStateComponent < ViewComponent::Base
  def initialize(text = nil)
    @text = text
  end

  def call
    content_tag :div, class: "w-full rounded-none border-0 bg-white p-0 shadow-none sm:rounded-lg sm:border sm:border-dashed sm:border-slate-300 sm:bg-white sm:p-6", data: { key: "empty-state" } do
      content_tag :div, class: "space-y-6 text-center py-12", data: { key: "empty-state.body" } do
        body
      end
    end
  end

  private

  def body
    content.presence || content_tag(:p, @text, class: "text-slate-500")
  end
end
