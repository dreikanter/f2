require "test_helper"

class ChangelogHelperTest < ActionView::TestCase
  include ChangelogHelper

  test "#changelog_entry should wrap backtick spans in code tags" do
    result = changelog_entry("Links with `http` or `https` now match.")

    assert_equal "Links with <code class=\"font-mono text-sm\">http</code> " \
      "or <code class=\"font-mono text-sm\">https</code> now match.", result
  end

  test "#changelog_entry should escape HTML in plain text" do
    result = changelog_entry("Posts with <script> tags & quotes.")

    assert_equal "Posts with &lt;script&gt; tags &amp; quotes.", result
  end

  test "#changelog_entry should escape HTML inside code spans" do
    result = changelog_entry("Use `<details>` for that.")

    assert_equal "Use <code class=\"font-mono text-sm\">&lt;details&gt;</code> for that.", result
  end

  test "#changelog_entry should leave an unmatched backtick as-is" do
    assert_equal "A stray ` backtick.", changelog_entry("A stray ` backtick.")
  end

  test "#changelog_date should format the date for reading" do
    assert_equal "July 3, 2026", changelog_date(Date.new(2026, 7, 3))
  end
end
