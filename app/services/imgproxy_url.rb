# Builds signed imgproxy URLs for resized image previews.
#
# imgproxy verifies an HMAC-SHA256 signature on every request (see
# docs/deployment-imgproxy.md), so preview URLs must be generated here with the
# shared key and salt. When imgproxy isn't configured — typically local
# development and tests — the original source URL is returned unchanged so
# previews still render straight from the source image.
class ImgproxyUrl
  # @param source_url [String] original image URL
  # @param width [Integer] target width in pixels
  # @param height [Integer] target height in pixels
  # @return [String] signed imgproxy URL, or source_url when unconfigured/blank
  def self.thumbnail(source_url, width:, height:)
    new(source_url, width: width, height: height).url
  end

  def initialize(source_url, width:, height:)
    @source_url = source_url
    @width = width
    @height = height
  end

  def url
    return source_url.to_s if source_url.blank? || !configured?

    "#{endpoint}/#{signature}#{path}"
  end

  private

  attr_reader :source_url, :width, :height

  # Resize to fill an exact width x height box, cropping the overflow.
  def path
    @path ||= "/rs:fill:#{width}:#{height}/#{encoded_source}"
  end

  def encoded_source
    Base64.urlsafe_encode64(source_url, padding: false)
  end

  def signature
    digest = OpenSSL::HMAC.digest("sha256", key, salt + path)
    Base64.urlsafe_encode64(digest, padding: false)
  end

  def configured?
    endpoint.present? && config[:key].present? && config[:salt].present?
  end

  def endpoint
    config[:endpoint].to_s.chomp("/").presence
  end

  def key
    @key ||= [config[:key]].pack("H*")
  end

  def salt
    @salt ||= [config[:salt]].pack("H*")
  end

  def config
    @config ||= Rails.application.credentials.imgproxy || {}
  end
end
