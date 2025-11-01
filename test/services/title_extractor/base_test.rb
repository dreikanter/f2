require "test_helper"

class TitleExtractor::BaseTest < ActiveSupport::TestCase
  def response
    @response ||= HttpClient::Response.new(status: 200, body: "test body")
  end

  def extractor
    @extractor ||= TitleExtractor::Base.new("https://example.com", response)
  end

  test "#initialize should set url and response" do
    assert_equal "https://example.com", extractor.url
    assert_equal response, extractor.response
  end

  test "#title should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      extractor.title
    end
    assert_equal "Subclasses must implement #title", error.message
  end
end
