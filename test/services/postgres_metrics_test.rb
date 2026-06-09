require "test_helper"

class PostgresMetricsTest < ActiveSupport::TestCase
  test "#database_size should return a positive byte count" do
    assert_operator PostgresMetrics.database_size, :>, 0
  end

  test "#table_sizes should map table label sets to positive byte counts" do
    sizes = PostgresMetrics.table_sizes

    assert_operator sizes.fetch({ table: "users" }), :>, 0
    assert_operator sizes.fetch({ table: "feeds" }), :>, 0
  end
end
