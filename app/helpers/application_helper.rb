module ApplicationHelper
  def page_header(title, &block)
    if block_given?
      content_tag :div, class: "d-flex justify-content-between align-items-center mb-4" do
        content_tag(:h1, title) + capture(&block)
      end
    else
      content_tag :div, class: "mb-4" do
        content_tag :h1, title
      end
    end
  end
end