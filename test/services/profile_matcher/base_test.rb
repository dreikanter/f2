require "test_helper"

class ProfileMatcher::BaseTest < ActiveSupport::TestCase
  def response
    @response ||= HttpClient::Response.new(status: 200, body: "test body")
  end

  def matcher
    @matcher ||= ProfileMatcher::Base.new("https://example.com", response)
  end

  test "should initialize with url and response" do
    assert_equal "https://example.com", matcher.url
    assert_equal response, matcher.response
  end

  test "match? should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      matcher.match?
    end
    assert_equal "Subclasses must implement #match?", error.message
  end
end
