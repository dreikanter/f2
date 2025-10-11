require "test_helper"

class ComponentOptionsHelperTest < ActionView::TestCase
  test "human_readable_cron returns 'not configured' for blank expression" do
    assert_equal "not configured", human_readable_cron(nil)
    assert_equal "not configured", human_readable_cron("")
  end

  test "human_readable_cron returns readable text for common patterns" do
    assert_equal "every 30 minutes", human_readable_cron("*/30 * * * *")
    assert_equal "every hour", human_readable_cron("0 * * * *")
    assert_equal "every 6 hours", human_readable_cron("0 */6 * * *")
    assert_equal "daily at midnight", human_readable_cron("0 0 * * *")
  end

  test "human_readable_cron returns 'using custom schedule' for unknown patterns" do
    assert_equal "using custom schedule", human_readable_cron("15 2 * * 1-5")
  end

  test "cron_expression_details returns nil for blank expression" do
    assert_nil cron_expression_details(nil)
    assert_nil cron_expression_details("")
  end

  test "cron_expression_details returns nil for common patterns" do
    assert_nil cron_expression_details("*/30 * * * *")
    assert_nil cron_expression_details("0 * * * *")
    assert_nil cron_expression_details("0 */6 * * *")
    assert_nil cron_expression_details("0 0 * * *")
  end

  test "cron_expression_details returns expression for custom patterns" do
    custom_cron = "15 2 * * 1-5"
    assert_equal custom_cron, cron_expression_details(custom_cron)
  end

  test "cron_expression_options returns options for form select with capitalized labels" do
    expected = [
      ["Every 30 minutes", "*/30 * * * *"],
      ["Every hour", "0 * * * *"],
      ["Every 6 hours", "0 */6 * * *"],
      ["Daily at midnight", "0 0 * * *"]
    ]

    assert_equal expected, cron_expression_options
  end
end
