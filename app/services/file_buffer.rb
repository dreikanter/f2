# Loads files to memory from URLs or local file paths
#
# @example Load from URL
#   io, content_type = FileBuffer.new("https://example.com/image.jpg").load
#
# @example Load from local file
#   io, content_type = FileBuffer.new("/path/to/file.png").load
#
class FileBuffer
  class Error < StandardError; end

  attr_reader :url, :http_client

  # Initialize a new FileBuffer
  #
  # @param url [String] URL or local file path to load
  # @param http_client [HttpClient, nil] optional HTTP client for testing
  def initialize(url, http_client: nil)
    @url = url
    @http_client = http_client
  end

  # Load the file into memory
  #
  # @return [Array<StringIO, String>] tuple of [StringIO with binary content, content_type]
  # @raise [FileBuffer::Error] if the file cannot be loaded
  def load
    if File.exist?(url)
      local_file_to_io
    else
      url_to_io
    end
  rescue HttpClient::Error => e
    raise Error, "Failed to download attachment from #{url}: #{e.message}"
  rescue => e
    raise Error, "Failed to download attachment from #{url}: #{e.message}"
  end

  private

  def local_file_to_io
    content = File.binread(url)
    content_type = local_file_content_type
    io = StringIO.new(content)
    io.set_encoding(Encoding::BINARY)
    [io, content_type]
  end

  def url_to_io
    client = http_client || HttpClient.build
    response = client.get(url)

    unless response.success?
      raise Error, "Failed to download attachment from #{url}: HTTP #{response.status}"
    end

    io = StringIO.new(response.body)
    io.set_encoding(Encoding::BINARY)
    io.rewind

    [io, url_content_type]
  end

  def local_file_content_type
    MiniMime.lookup_by_filename(url)&.content_type || "application/octet-stream"
  end

  def url_content_type
    uri = URI(url)
    MiniMime.lookup_by_filename(uri.path)&.content_type || "image/jpeg"
  end
end
