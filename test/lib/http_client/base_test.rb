require "test_helper"

class HttpClient::BaseTest < ActiveSupport::TestCase
  def base
    @base ||= HttpClient::Base.new
  end

  test "#get should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      base.get("https://example.com")
    end
    assert_equal "Subclasses must implement #get", error.message
  end

  test "#post should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      base.post("https://example.com")
    end
    assert_equal "Subclasses must implement #post", error.message
  end

  test "#put should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      base.put("https://example.com")
    end
    assert_equal "Subclasses must implement #put", error.message
  end

  test "#delete should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      base.delete("https://example.com")
    end
    assert_equal "Subclasses must implement #delete", error.message
  end

  test "#get should accept headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      base.get("https://example.com", headers: { "Accept" => "application/json" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #get", error.message
  end

  test "#post should accept body, headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      base.post("https://example.com", body: "test", headers: { "Content-Type" => "text/plain" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #post", error.message
  end

  test "#put should accept body, headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      base.put("https://example.com", body: "test", headers: { "Content-Type" => "text/plain" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #put", error.message
  end

  test "#delete should accept headers and options parameters" do
    error = assert_raises(NotImplementedError) do
      base.delete("https://example.com", headers: { "Accept" => "application/json" }, options: { timeout: 30 })
    end
    assert_equal "Subclasses must implement #delete", error.message
  end
end
