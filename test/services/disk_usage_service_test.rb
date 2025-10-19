require "test_helper"

class DiskUsageServiceTest < ActiveSupport::TestCase
  test "should return hash with all expected keys" do
    result = DiskUsageService.new.call

    assert_instance_of Hash, result
    assert result.key?(:free_space)
    assert result.key?(:postgres_usage)
    assert result.key?(:table_usage)
    assert result.key?(:vacuum_stats)
    assert result.key?(:autovacuum_settings)
  end

  test "should return free space as string" do
    result = DiskUsageService.new.call

    assert_instance_of String, result[:free_space]
    assert_not result[:free_space].empty?
  end

  test "should return postgres usage as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:postgres_usage]
    assert result[:postgres_usage] >= 0
  end

  test "should return table usage as array" do
    result = DiskUsageService.new.call

    assert_instance_of Array, result[:table_usage]
    assert result[:table_usage].all? { |row| row.is_a?(Hash) }

    if result[:table_usage].any?
      first_row = result[:table_usage].first
      assert first_row.key?("table_name")
      assert first_row.key?("total_size")
    end
  end

  test "should return vacuum stats as array" do
    result = DiskUsageService.new.call

    assert_instance_of Array, result[:vacuum_stats]
    assert result[:vacuum_stats].all? { |row| row.is_a?(Hash) }

    if result[:vacuum_stats].any?
      first_row = result[:vacuum_stats].first
      assert first_row.key?("relname")
      assert first_row.key?("n_live_tup")
      assert first_row.key?("n_dead_tup")
    end
  end

  test "should return autovacuum settings as array" do
    result = DiskUsageService.new.call

    assert_instance_of Array, result[:autovacuum_settings]
    assert result[:autovacuum_settings].all? { |row| row.is_a?(Hash) }
    assert result[:autovacuum_settings].any?

    first_row = result[:autovacuum_settings].first
    assert first_row.key?("name")
    assert first_row.key?("setting")
    assert first_row["name"].start_with?("autovacuum")
  end
end
