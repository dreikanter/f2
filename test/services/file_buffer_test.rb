require "test_helper"

class FileBufferTest < ActiveSupport::TestCase
  def test_file_path
    @test_file_path ||= file_fixture("feeds/rss/feed.xml").to_s
  end

  test "should load local file and return StringIO with content type" do
    buffer = FileBuffer.new(test_file_path)
    io, content_type = buffer.load

    assert_instance_of StringIO, io
    assert_equal "application/xml", content_type
    assert io.string.include?("<?xml")
    assert_equal Encoding::BINARY, io.string.encoding
  end

  test "should detect content type for local image file" do
    image_path = file_fixture("test_image.jpg").to_s

    buffer = FileBuffer.new(image_path)
    io, content_type = buffer.load

    assert_equal "image/jpeg", content_type
  end

  test "should download from URL and return StringIO with content type" do
    url = "https://example.com/image.jpg"
    response_body = file_fixture("test_image.jpg").binread
    response = Struct.new(:success?, :body).new(true, response_body)

    http_client = Minitest::Mock.new
    http_client.expect(:get, response, [url])

    buffer = FileBuffer.new(url, http_client: http_client)
    io, content_type = buffer.load

    assert_instance_of StringIO, io
    assert_equal "image/jpeg", content_type
    assert_equal response_body, io.string
    assert_equal Encoding::BINARY, io.string.encoding
    http_client.verify
  end

  test "should use image/jpeg as fallback for URLs without file extension" do
    url = "https://example.com/unknown"
    response_body = file_fixture("test_image.jpg").binread
    response = Struct.new(:success?, :body).new(true, response_body)

    http_client = Minitest::Mock.new
    http_client.expect(:get, response, [url])

    buffer = FileBuffer.new(url, http_client: http_client)
    io, content_type = buffer.load

    assert_equal "image/jpeg", content_type
    http_client.verify
  end

  test "should raise error when HTTP request fails" do
    url = "https://example.com/image.jpg"
    response = Struct.new(:success?, :status).new(false, 404)

    http_client = Minitest::Mock.new
    http_client.expect(:get, response, [url])

    buffer = FileBuffer.new(url, http_client: http_client)

    assert_raises(FileBuffer::Error) do
      buffer.load
    end

    http_client.verify
  end

  test "should raise error for other exceptions" do
    url = "https://example.com/image.jpg"
    http_client = Minitest::Mock.new

    http_client.expect(:get, [url]) do
      raise StandardError, "Unexpected error"
    end

    buffer = FileBuffer.new(url, http_client: http_client)

    assert_raises(FileBuffer::Error) do
      buffer.load
    end
  end
end
