require "test_helper"

class ComponentOptionsHelperTest < ActionView::TestCase
  test "loader_options returns loader options" do
    expected = [["HTTP", "http"]]
    result = loader_options

    assert_equal expected, result
  end

  test "processor_options returns processor options" do
    expected = [["RSS/XML", "rss"]]
    result = processor_options

    assert_equal expected, result
  end

  test "normalizer_options returns normalizer options" do
    expected = [["RSS", "rss"]]
    result = normalizer_options

    assert_equal expected, result
  end
end
