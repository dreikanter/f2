require "test_helper"

class LlmClient::RateTableTest < ActiveSupport::TestCase
  setup { LlmClient::RateTable.reload! }
  teardown { LlmClient::RateTable.reload! }

  def usage(input: 0, output: 0, cache_write: 0, cache_read: 0)
    LlmClient::RateTable::Usage.new(
      input_tokens: input,
      output_tokens: output,
      cache_write_tokens: cache_write,
      cache_read_tokens: cache_read
    )
  end

  test "#rate_for should return a Rate for a known provider+model pair" do
    rate = LlmClient::RateTable.rate_for(provider: "anthropic", model: "claude-sonnet-4-6")

    assert_kind_of LlmClient::RateTable::Rate, rate
    assert_equal 3.0, rate.input_per_million
    assert_equal 15.0, rate.output_per_million
  end

  test "#rate_for should accept symbol provider keys" do
    rate = LlmClient::RateTable.rate_for(provider: :anthropic, model: "claude-haiku-4-5")

    assert_kind_of LlmClient::RateTable::Rate, rate
    assert_in_delta 0.80, rate.input_per_million, 0.0001
  end

  test "#rate_for should return nil for an unknown model" do
    assert_nil LlmClient::RateTable.rate_for(provider: "anthropic", model: "claude-imaginary")
  end

  test "#rate_for should return nil for an unknown provider" do
    assert_nil LlmClient::RateTable.rate_for(provider: "made-up", model: "claude-sonnet-4-6")
  end

  test "#cost_for should compute cost in cents from input and output tokens" do
    # claude-sonnet-4-6: $3 input / $15 output per million.
    # 1_000_000 input + 200_000 output = $3.00 + $3.00 = $6.00 = 600 cents
    cost = LlmClient::RateTable.cost_for(
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      usage: usage(input: 1_000_000, output: 200_000)
    )

    assert_equal 600, cost
  end

  test "#cost_for should add prompt-cache token costs" do
    # claude-sonnet-4-6: cache_write $3.75/M, cache_read $0.30/M.
    # 1M input + 1M cache_write + 1M cache_read = $3.00 + $3.75 + $0.30 = $7.05 = 705 cents
    cost = LlmClient::RateTable.cost_for(
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      usage: usage(input: 1_000_000, cache_write: 1_000_000, cache_read: 1_000_000)
    )

    assert_equal 705, cost
  end

  test "#cost_for should return 0 for an unknown model" do
    assert_equal 0, LlmClient::RateTable.cost_for(
      provider: "anthropic",
      model: "claude-imaginary",
      usage: usage(input: 1_000_000)
    )
  end

  test "should return an empty table when the rates file is missing" do
    original = LlmClient::RateTable::PATH
    LlmClient::RateTable.send(:remove_const, :PATH)
    LlmClient::RateTable.const_set(:PATH, Rails.root.join("config/__does_not_exist__.yml"))
    LlmClient::RateTable.reload!

    assert_nil LlmClient::RateTable.rate_for(provider: "anthropic", model: "claude-sonnet-4-6")
    assert_equal 0, LlmClient::RateTable.cost_for(
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      usage: usage(input: 1_000_000)
    )
  ensure
    LlmClient::RateTable.send(:remove_const, :PATH)
    LlmClient::RateTable.const_set(:PATH, original)
    LlmClient::RateTable.reload!
  end
end
