module IdentifierHelper
  UUID_SUFFIX_LENGTH = 5
  UUID_LINK_CLASSES = "font-mono underline underline-offset-2 transition hover:text-heading".freeze

  def short_uuid(value)
    value.to_s.last(UUID_SUFFIX_LENGTH)
  end

  def uuid_label(value, prefix: nil)
    [prefix, short_uuid(value)].compact_blank.join(" ")
  end

  def uuid_reference(value, path: nil, prefix: nil, **html_options)
    html_options[:title] ||= value.to_s
    html_options[:class] ||= UUID_LINK_CLASSES
    label = uuid_label(value, prefix: prefix)

    path ? link_to(label, path, **html_options) : tag.span(label, **html_options)
  end
end
