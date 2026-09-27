require "test_helper"

class FeaturesTest < ActiveSupport::TestCase
  test ".ai? should reflect the configured flag" do
    assert Features.ai?

    Rails.configuration.x.features.stub(:ai, false) do
      assert_not Features.ai?
    end
  end

  test ".external_search? should reflect the configured flag" do
    assert_not Features.external_search?

    Rails.configuration.x.features.stub(:external_search, true) do
      assert Features.external_search?
    end
  end
end
