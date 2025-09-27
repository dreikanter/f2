require "test_helper"

class HttpClient::BaseTest < ActiveSupport::TestCase
  def setup
    @base = HttpClient::Base.new
  end

  test "get raises NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      @base.get("https://example.com")
    end
    assert_equal "Subclasses must implement #get", error.message
  end

  test "post raises NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      @base.post("https://example.com")
    end
    assert_equal "Subclasses must implement #post", error.message
  end

  test "put raises NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      @base.put("https://example.com")
    end
    assert_equal "Subclasses must implement #put", error.message
  end

  test "delete raises NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      @base.delete("https://example.com")
    end
    assert_equal "Subclasses must implement #delete", error.message
  end

  test "get accepts headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      @base.get("https://example.com", headers: { "Accept" => "application/json" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #get", error.message
  end

  test "post accepts body, headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      @base.post("https://example.com", body: "test", headers: { "Content-Type" => "text/plain" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #post", error.message
  end

  test "put accepts body, headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      @base.put("https://example.com", body: "test", headers: { "Content-Type" => "text/plain" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #put", error.message
  end

  test "delete accepts headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      @base.delete("https://example.com", headers: { "Accept" => "application/json" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #delete", error.message
  end
end