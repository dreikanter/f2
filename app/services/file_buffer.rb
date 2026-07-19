# Loads files into memory from URLs or local file paths.
#
# @example Load from URL
#   io, content_type = FileBuffer.new.load("https://example.com/image.jpg")
#
# @example Load from local file
#   io, content_type = FileBuffer.new.load("/path/to/file.png")
#
class FileBuffer
  DEFAULT_CONTENT_TYPE = "application/octet-stream"

  # Some image hosts (notably Reddit's CDN, *.redd.it) reject requests without a
  # User-Agent with HTTP 403. Net::HTTP sends none by default, so we set one.
  USER_AGENT = "Feeder".freeze

  class Error < StandardError; end

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
  rescue Error
    raise
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
    [io, content_type]
  end

  def url_to_io(url)
    normalized_url = normalize_url(url)
    # Attachment URLs are model- or source-supplied: fetch public-only, so a
    # redirect can't reach a private/internal address at publish time (SSRF).
    response = http_client.get(
      normalized_url,
      headers: { "User-Agent" => USER_AGENT },
      options: { validate_url: PublicUrl.method(:safe?) }
    )

    unless response.success?
      raise Error, "Failed to download attachment from #{url}: HTTP #{response.status}"
    end

    io = StringIO.new(response.body)
    io.set_encoding(Encoding::BINARY)

    content_type = url_content_type(normalized_url, response.body)

    [io, content_type]
  end

  # Normalize the URL so it can be handled by Ruby's URI/Net::HTTP, which reject
  # non-ASCII input. Addressable percent-encodes non-ASCII characters in the path
  # and query and converts non-ASCII hosts to punycode, leaving valid URLs intact.
  def normalize_url(url)
    Addressable::URI.parse(url).normalize.to_s
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
