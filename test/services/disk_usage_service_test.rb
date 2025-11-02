require "test_helper"

class DiskUsageServiceTest < ActiveSupport::TestCase
  test "#call should return hash with all expected keys" do
    result = DiskUsageService.new.call

    assert_instance_of Hash, result
    assert result.key?(:total_space)
    assert result.key?(:used_space)
    assert result.key?(:free_space)
    assert result.key?(:postgres_usage)
    assert result.key?(:other_used_space)
    assert result.key?(:postgres_percentage)
    assert result.key?(:other_used_percentage)
    assert result.key?(:free_percentage)
    assert result.key?(:table_usage)
    assert result.key?(:vacuum_stats)
    assert result.key?(:autovacuum_settings)
  end

  test "#call should return free space as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:free_space]
    assert result[:free_space] >= 0
  end

  test "#call should return postgres usage as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:postgres_usage]
    assert result[:postgres_usage] >= 0
  end

  test "#call should return table usage as array" do
    result = DiskUsageService.new.call

    assert_instance_of Array, result[:table_usage]
    assert result[:table_usage].all? { |row| row.is_a?(Hash) }

    if result[:table_usage].any?
      first_row = result[:table_usage].first
      assert first_row.key?("table_name")
      assert first_row.key?("total_size")
    end
  end

  test "#call should return vacuum stats as array" do
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

  test "#call should return autovacuum settings as array" do
    result = DiskUsageService.new.call

    assert_instance_of Array, result[:autovacuum_settings]
    assert result[:autovacuum_settings].all? { |row| row.is_a?(Hash) }
    assert result[:autovacuum_settings].any?

    first_row = result[:autovacuum_settings].first
    assert first_row.key?("name")
    assert first_row.key?("setting")
    assert first_row["name"].start_with?("autovacuum")
  end

  test "#call should return total space as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:total_space]
    assert result[:total_space] > 0
  end

  test "#call should return used space as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:used_space]
    assert result[:used_space] >= 0
  end

  test "#call should return other used space as integer" do
    result = DiskUsageService.new.call

    assert_instance_of Integer, result[:other_used_space]
    assert result[:other_used_space] >= 0
    assert_equal result[:used_space] - result[:postgres_usage], result[:other_used_space]
  end

  test "#call should return postgres percentage as float" do
    result = DiskUsageService.new.call

    assert_instance_of Float, result[:postgres_percentage]
    assert result[:postgres_percentage] >= 0
    assert result[:postgres_percentage] <= 100
  end

  test "#call should return other used percentage as float" do
    result = DiskUsageService.new.call

    assert_instance_of Float, result[:other_used_percentage]
    assert result[:other_used_percentage] >= 0
    assert result[:other_used_percentage] <= 100
  end

  test "#call should return free percentage as float" do
    result = DiskUsageService.new.call

    assert_instance_of Float, result[:free_percentage]
    assert result[:free_percentage] >= 0
    assert result[:free_percentage] <= 100
  end

  test "#call percentages should sum to approximately 100" do
    result = DiskUsageService.new.call

    total_percentage = result[:postgres_percentage] + result[:other_used_percentage] + result[:free_percentage]
    assert_in_delta 100.0, total_percentage, 0.5
  end
end
