require "test_helper"

class WebhookPayloadTest < ActiveSupport::TestCase
  test "#content should return an empty string when absent" do
    assert_equal "", WebhookPayload.new({}).content
    assert_equal "Hello", WebhookPayload.new({ "content" => "Hello" }).content
  end

  test "#source_url should strip surrounding whitespace" do
    assert_equal "https://example.com", WebhookPayload.new({ "source_url" => "  https://example.com  " }).source_url
  end

  test "#source_url should return nil when blank" do
    assert_nil WebhookPayload.new({}).source_url
    assert_nil WebhookPayload.new({ "source_url" => "   " }).source_url
  end

  test "#images should return an array of strings" do
    assert_equal [], WebhookPayload.new({}).images
    assert_equal ["https://example.com/a.jpg"], WebhookPayload.new({ "images" => ["https://example.com/a.jpg"] }).images
  end

  test "#comments should return an array of strings" do
    assert_equal [], WebhookPayload.new({}).comments
    assert_equal ["Nice"], WebhookPayload.new({ "comments" => ["Nice"] }).comments
  end

  test "#explicit_uid should strip surrounding whitespace" do
    assert_equal "article-42", WebhookPayload.new({ "uid" => "  article-42  " }).explicit_uid
    assert_equal "", WebhookPayload.new({}).explicit_uid
  end

  test "#uid_given? should tell a missing uid from a blank one" do
    assert_not WebhookPayload.new({}).uid_given?
    assert WebhookPayload.new({ "uid" => "   " }).uid_given?
  end

  test "#raw_published_at should return an empty string when absent" do
    assert_equal "", WebhookPayload.new({}).raw_published_at
    assert_equal "2026-01-01T00:00:00Z", WebhookPayload.new({ "published_at" => "2026-01-01T00:00:00Z" }).raw_published_at
  end

  test "#to_h should return the wrapped hash for storage and schema checks" do
    data = { "content" => "Hello" }

    assert_same data, WebhookPayload.new(data).to_h
  end
end
