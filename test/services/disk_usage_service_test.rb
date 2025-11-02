require "test_helper"
require "ostruct"

class DiskUsageServiceTest < ActiveSupport::TestCase
  def stub_df_command(total_kb: 1000000, used_kb: 200000, avail_kb: 750000)
    df_output = <<~DF
      Filesystem     1024-blocks      Used Available Capacity  Mounted on
      /dev/disk3s1s1   #{total_kb}  #{used_kb} #{avail_kb}     4%    /
    DF

    -> { [df_output, OpenStruct.new(success?: true, exitstatus: 0)] }
  end

  test "#call should return hash with all expected keys" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

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
    service = DiskUsageService.new(df_command: stub_df_command(avail_kb: 750000))
    result = service.call

    assert_instance_of Integer, result[:free_space]
    assert_equal 750000 * 1024, result[:free_space]
  end

  test "#call should return postgres usage as integer" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Integer, result[:postgres_usage]
    assert result[:postgres_usage] >= 0
  end

  test "#call should return table usage as array" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Array, result[:table_usage]
    assert result[:table_usage].all? { |row| row.is_a?(Hash) }

    if result[:table_usage].any?
      first_row = result[:table_usage].first
      assert first_row.key?("table_name")
      assert first_row.key?("total_size")
    end
  end

  test "#call should return vacuum stats as array" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

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
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Array, result[:autovacuum_settings]
    assert result[:autovacuum_settings].all? { |row| row.is_a?(Hash) }
    assert result[:autovacuum_settings].any?

    first_row = result[:autovacuum_settings].first
    assert first_row.key?("name")
    assert first_row.key?("setting")
    assert first_row["name"].start_with?("autovacuum")
  end

  test "#call should return total space as integer" do
    service = DiskUsageService.new(df_command: stub_df_command(total_kb: 1000000))
    result = service.call

    assert_instance_of Integer, result[:total_space]
    assert_equal 1000000 * 1024, result[:total_space]
  end

  test "#call should return used space as integer" do
    service = DiskUsageService.new(df_command: stub_df_command(used_kb: 200000))
    result = service.call

    assert_instance_of Integer, result[:used_space]
    assert_equal 200000 * 1024, result[:used_space]
  end

  test "#call should return other used space as integer" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Integer, result[:other_used_space]
    assert result[:other_used_space] >= 0
    assert_equal result[:used_space] - result[:postgres_usage], result[:other_used_space]
  end

  test "#call should return postgres percentage as float" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Float, result[:postgres_percentage]
    assert result[:postgres_percentage] >= 0
    assert result[:postgres_percentage] <= 100
  end

  test "#call should return other used percentage as float" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Float, result[:other_used_percentage]
    assert result[:other_used_percentage] >= 0
    assert result[:other_used_percentage] <= 100
  end

  test "#call should return free percentage as float" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    assert_instance_of Float, result[:free_percentage]
    assert result[:free_percentage] >= 0
    assert result[:free_percentage] <= 100
  end

  test "#call percentages should sum to approximately 100" do
    service = DiskUsageService.new(df_command: stub_df_command)
    result = service.call

    total_percentage = result[:postgres_percentage] + result[:other_used_percentage] + result[:free_percentage]
    assert_in_delta 100.0, total_percentage, 0.5
  end

  test "#call should handle df command failure" do
    df_command = -> { ["", OpenStruct.new(success?: false, exitstatus: 1)] }
    service = DiskUsageService.new(df_command: df_command)

    error = assert_raises(RuntimeError) do
      service.call
    end

    assert_match(/df command failed/, error.message)
  end

  test "#call should handle zero accountable space" do
    service = DiskUsageService.new(df_command: stub_df_command(total_kb: 0, used_kb: 0, avail_kb: 0))
    result = service.call

    assert_equal 0.0, result[:postgres_percentage]
    assert_equal 0.0, result[:other_used_percentage]
    assert_equal 0.0, result[:free_percentage]
  end

  test "#call should calculate percentages correctly with known values" do
    service = DiskUsageService.new(df_command: stub_df_command(total_kb: 1000000, used_kb: 200000, avail_kb: 750000))
    result = service.call

    accountable_space = (200000 + 750000) * 1024

    expected_postgres_pct = (result[:postgres_usage].to_f / accountable_space * 100).round(1)
    assert_equal expected_postgres_pct, result[:postgres_percentage]

    expected_free_pct = (750000.0 / 950000 * 100).round(1)
    assert_equal expected_free_pct, result[:free_percentage]
  end
end
