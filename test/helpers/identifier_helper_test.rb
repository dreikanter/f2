require "test_helper"

class IdentifierHelperTest < ActionView::TestCase
  test "#short_ref returns the final five characters" do
    assert_equal "1674a", short_ref("019f5bd6-d55f-7ac2-9d75-15be0cf1674a")
  end
end
