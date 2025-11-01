require "test_helper"

class FileBufferTest < ActiveSupport::TestCase
  test "#load should read local file and return StringIO with content type" do
    file = file_fixture("feeds/rss/feed.xml")
    io, content_type = FileBuffer.new.load(file.to_s)

    assert_instance_of StringIO, io
    assert_equal "application/xml", content_type
    assert_equal file.read, io.string
    assert_equal Encoding::BINARY, io.string.encoding
  end

  test "#load should detect content type for local image file" do
    image_path = file_fixture("test_image.jpg").to_s
    io, content_type = FileBuffer.new.load(image_path)

    assert_equal "image/jpeg", content_type
  end

  test "#load should download from URL and return StringIO with content type" do
    url = "https://example.com/image.jpg"
    response_body = file_fixture("test_image.jpg").binread

    stub_request(:get, url).to_return(status: 200, body: response_body)

    io, content_type = FileBuffer.new.load(url)

    assert_instance_of StringIO, io
    assert_equal "image/jpeg", content_type
    assert_equal response_body, io.string
    assert_equal Encoding::BINARY, io.string.encoding
  end

  test "#load should detect content type from file content when URL has no extension" do
    url = "https://example.com/unknown"
    response_body = file_fixture("test_image.jpg").binread

    stub_request(:get, url).to_return(status: 200, body: response_body)

    io, content_type = FileBuffer.new.load(url)

    assert_equal "image/png", content_type
  end

  test "#load should raise error when HTTP request fails" do
    url = "https://example.com/image.jpg"

    stub_request(:get, url).to_return(status: 404)

    assert_raises(FileBuffer::Error) do
      FileBuffer.new.load(url)
    end
  end

  test "#load should raise error for other exceptions" do
    url = "https://example.com/image.jpg"

    stub_request(:get, url).to_raise(StandardError.new("Unexpected error"))

    assert_raises(FileBuffer::Error) do
      FileBuffer.new.load(url)
    end
  end
end
