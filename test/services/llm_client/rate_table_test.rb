require "test_helper"

class LlmClient::RateTableTest < ActiveSupport::TestCase
  setup { LlmClient::RateTable.reload! }
  teardown { LlmClient::RateTable.reload! }

  def usage(input: 0, output: 0, cache_write: 0, cache_read: 0)
    LlmClient::ProviderResponse.new(
      payload: nil,
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

  test "#cost_for should return nil for an unknown model" do
    assert_nil LlmClient::RateTable.cost_for(
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
    assert_nil LlmClient::RateTable.cost_for(
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      usage: usage(input: 1_000_000)
    )
  ensure
    LlmClient::RateTable.send(:remove_const, :PATH)
    LlmClient::RateTable.const_set(:PATH, original)
    LlmClient::RateTable.reload!
  end
  test "#cost_for should use published exact model pricing including explicit free rates" do
    cost = LlmClient::RateTable.cost_for(provider: "openai", model: "brand-new",
      usage: usage(input: 1_000_000, output: 500_000), pricing: { "input" => 2, "output" => 0 })
    assert_equal 200, cost
  end

  test "#cost_for should keep partial pricing unknown when an unpriced token category was used" do
    assert_nil LlmClient::RateTable.cost_for(provider: "anthropic", model: "claude-sonnet-4-6",
      usage: usage(input: 1_000_000, cache_read: 10), pricing: { "input" => 1 })
  end

  test "#cost_for should preserve missing fallback cache rates as unknown only when those tokens were used" do
    options = { provider: "openrouter", model: "anthropic/claude-sonnet-4-6" }
    rate = LlmClient::RateTable.rate_for(**options)
    assert_nil rate.cache_read_per_million
    assert_nil rate.cache_write_per_million

    assert_nil LlmClient::RateTable.cost_for(**options, usage: usage(cache_read: 10))
    assert_nil LlmClient::RateTable.cost_for(**options, usage: usage(cache_write: 10))
    assert_equal "0.0003".to_d, LlmClient::RateTable.cost_for(**options, usage: usage(input: 1))
  end

  test "#cost_for should preserve fractional cents with decimal arithmetic" do
    assert_equal "0.01035".to_d, LlmClient::RateTable.cost_for(
      provider: "openai", model: "new-model", usage: usage(input: 123, output: 456),
      pricing: { "input" => 0.1, "output" => 0.2 }
    )
  end

  test "#cost_for should accept an explicitly free cache rate and reject nonfinite prices" do
    assert_equal 0, LlmClient::RateTable.cost_for(provider: "openrouter", model: "new-model",
      usage: usage(cache_read: 10), pricing: { "cache_read" => 0 })

    [Float::INFINITY, Float::NAN].each do |price|
      assert_nil LlmClient::RateTable.cost_for(provider: "openai", model: "new-model",
        usage: usage(input: 1), pricing: { "input" => price })
    end
  end
end
