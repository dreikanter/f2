# A footer row for ListComponent lists that links to the full collection.
# Renders a centered, muted "View all" link styled to sit as the last item
# of the list.
class ViewAllListItemComponent < ViewComponent::Base
  def initialize(url:, data: {})
    @url = url
    @data = data
  end

  def call
    tag.li class: "px-5 py-3 text-center first:rounded-t-lg last:rounded-b-lg" do
      link_to "View all", @url, class: "text-sm font-medium text-muted transition hover:text-body", data: @data
    end
  end
end
