require "test_helper"

class LlmClient::OutputLimitTest < ActiveSupport::TestCase
  test ".for should honor smaller limits without exceeding the application allowance" do
    [[1, 1], [1_024, 1_024], [128_000, 8_192]].each do |advisory, expected|
      credential = build(:ai_credential, available_models: [
        { "id" => "new-model", "metadata" => { "max_output_tokens" => advisory } }
      ])

      assert_equal expected, LlmClient::OutputLimit.for(credential, "new-model")
    end
  end

  test ".for should ignore missing invalid and non-integral token limits" do
    [nil, 0, -1, "1024", 0.5, 1_024.5, true].each do |advisory|
      credential = build(:ai_credential, available_models: [
        { "id" => "new-model", "metadata" => { "max_output_tokens" => advisory } }
      ])

      assert_equal 8_192, LlmClient::OutputLimit.for(credential, "new-model")
      assert_equal 8_192, LlmClient::OutputLimit.for(credential, "unlisted-model")
    end
  end
end
