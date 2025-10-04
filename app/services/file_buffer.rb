# Loads files to memory from URLs or local file paths
#
# @example Load from URL
#   io, content_type = FileBuffer.new("https://example.com/image.jpg").load
#
# @example Load from local file
#   io, content_type = FileBuffer.new("/path/to/file.png").load
#
class FileBuffer
  DEFAULT_CONTENT_TYPE = "application/octet-stream"

  class Error < StandardError; end

  # Initialize a new FileBuffer
  #
  # @param url [String] URL or local file path to load
  # @param http_client [HttpClient, nil] optional HTTP client for testing
  def initialize(http_client: nil)
    @http_client = http_client
  end

  # Load the file into memory
  #
  # @return [Array<StringIO, String>] tuple of [StringIO with binary content, content_type]
  # @raise [FileBuffer::Error] if the file cannot be loaded
  def load(url)
    if File.exist?(url)
      load_local_file(url)
    else
      url_to_io(url)
    end
  rescue => e
    raise Error, "Failed to download attachment from #{url}: #{e.message}"
  end

  private

  def http_client
    @http_client ||= HttpClient.build
  end

  def load_local_file(path)
    content = File.binread(path)
    io = StringIO.new(content)
    io.set_encoding(Encoding::BINARY)
    content_type = local_file_content_type(path)
    [io , content_type]
  end

  def url_to_io(url)
    response = http_client.get(url)

    unless response.success?
      raise Error, "Failed to download attachment from #{url}: HTTP #{response.status}"
    end

    io = StringIO.new(response.body)
    io.set_encoding(Encoding::BINARY)

    content_type = url_content_type(url, response.body)

    [io, content_type]
  end

  def local_file_content_type(path)
    Marcel::MimeType.for(name: path) || DEFAULT_CONTENT_TYPE
  end

  # Attempt to detect content typoe from file name. Fallback to content parsing.
  def url_content_type(url, body)
    uri = URI(url)
    type = Marcel::MimeType.for(name: uri.path)
    return type if type && type != DEFAULT_CONTENT_TYPE

    Marcel::MimeType.for(StringIO.new(body), name: uri.path)
  end
end
