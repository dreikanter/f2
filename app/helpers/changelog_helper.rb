module ChangelogHelper
  # Entries are plain text except for `backtick` spans, which become <code>.
  # Splitting on the capture group yields alternating text/code parts, and
  # safe_join escapes the text ones.
  def changelog_entry(text)
    parts = text.split(/`([^`]+)`/).map.with_index do |part, index|
      index.odd? ? tag.code(part, class: "font-mono text-sm") : part
    end

    safe_join(parts)
  end

  def changelog_date(date)
    date.strftime("%B %-d, %Y")
  end
end
