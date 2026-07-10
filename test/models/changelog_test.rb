require "test_helper"

class ChangelogTest < ActiveSupport::TestCase
  test "#sections should group entries under date headings" do
    markdown = <<~MARKDOWN
      # Changelog

      User-facing changes, newest first.

      ## 2026-07-10

      - First entry.
      - Second entry.

      ## 2026-07-09

      - Older entry.
    MARKDOWN

    sections = Changelog.new(markdown).sections

    assert_equal 2, sections.size
    assert_equal Date.new(2026, 7, 10), sections.first.date
    assert_equal ["First entry.", "Second entry."], sections.first.entries
    assert_equal Date.new(2026, 7, 9), sections.last.date
    assert_equal ["Older entry."], sections.last.entries
  end

  test "#sections should ignore bullets before the first date heading" do
    markdown = <<~MARKDOWN
      - Stray bullet.

      ## 2026-07-10

      - Real entry.
    MARKDOWN

    sections = Changelog.new(markdown).sections

    assert_equal 1, sections.size
    assert_equal ["Real entry."], sections.first.entries
  end

  test "#sections should be empty when there are no date headings" do
    assert_empty Changelog.new("# Changelog\n\nNothing yet.\n").sections
  end

  test "#sections should skip non-date second-level headings" do
    markdown = <<~MARKDOWN
      ## Unreleased

      - Not dated.

      ## 2026-07-10

      - Dated entry.
    MARKDOWN

    sections = Changelog.new(markdown).sections

    assert_equal 1, sections.size
    assert_equal ["Dated entry."], sections.first.entries
  end

  test ".load should parse the project changelog" do
    sections = Changelog.load.sections

    assert sections.any?
    assert sections.all? { |section| section.entries.any? }
  end
end
