class IconComponent < ViewComponent::Base
  ICONS_PATH = Rails.root.join("node_modules", "bootstrap-icons", "icons")

  def initialize(name, css_class: nil, aria_hidden: true, aria_label: nil)
    @name = name
    @css_class = css_class
    @aria_hidden = aria_hidden
    @aria_label = aria_label
  end

  def svg_content
    @svg_content ||= process_svg(read_svg_file)
  end

  def svg_classes
    class_names("inline-block", @css_class)
  end

  def aria_attributes
    attrs = {}
    attrs["aria-hidden"] = @aria_hidden.to_s if @aria_hidden
    attrs["aria-label"] = @aria_label if @aria_label.present?
    attrs
  end

  private

  def read_svg_file
    file_path = ICONS_PATH.join("#{@name}.svg")

    if File.exist?(file_path)
      File.read(file_path)
    else
      fallback_icon
    end
  end

  def process_svg(svg_string)
    # Remove width, height, and class attributes from SVG
    # These will be controlled by our wrapper span
    svg_string
      .gsub(/\s+width="[^"]*"/, "")
      .gsub(/\s+height="[^"]*"/, "")
      .gsub(/\s+class="[^"]*"/, "")
  end

  def fallback_icon
    # If icon not found, return a simple circle as fallback
    '<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/></svg>'
  end
end
