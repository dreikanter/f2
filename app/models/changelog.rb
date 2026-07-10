# Parses CHANGELOG.md into dated sections of user-facing entries. The file
# format is line-based by convention: `## YYYY-MM-DD` headings with one-line
# bullets under each; anything else (title, intro prose) is skipped.
class Changelog
  Section = Data.define(:date, :entries)

  DATE_HEADING = /\A## (\d{4}-\d{2}-\d{2})\s*\z/
  ENTRY = /\A- (.+)\z/

  def self.load
    new(Rails.root.join("CHANGELOG.md").read)
  end

  attr_reader :sections

  def initialize(markdown)
    @sections = parse(markdown)
  end

  private

  def parse(markdown)
    sections = []

    markdown.each_line(chomp: true) do |line|
      if (heading = line.match(DATE_HEADING))
        sections << Section.new(date: Date.iso8601(heading[1]), entries: [])
      elsif (entry = line.match(ENTRY)) && sections.any?
        sections.last.entries << entry[1]
      end
    end

    sections
  end
end
