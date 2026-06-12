require "test_helper"

class PostgresMetricsTest < ActiveSupport::TestCase
  test "#database_size should return a positive byte count" do
    assert_operator PostgresMetrics.database_size, :>, 0
  end

  test "#table_sizes should map tracked table label sets to positive byte counts" do
    sizes = PostgresMetrics.table_sizes

    assert_equal PostgresMetrics::TRACKED_TABLES.sort, sizes.keys.map { |labels| labels[:table] }.sort
    sizes.each_value { |size| assert_operator size, :>, 0 }
  end

  test "#table_sizes should not include untracked tables" do
    assert_not_includes PostgresMetrics.table_sizes.keys, { table: "users" }
  end
end
