require "test_helper"

class ImgproxyUrlTest < ActiveSupport::TestCase
  KEY = "1a2b3c4d"
  SALT = "5e6f7a8b"

  def with_imgproxy_config(config)
    Rails.application.credentials.stub(:imgproxy, config) do
      yield
    end
  end

  test "#thumbnail should build a signed imgproxy url when configured" do
    source = "https://example.com/photo.jpg"

    with_imgproxy_config(endpoint: "https://imgproxy.example.com", key: KEY, salt: SALT) do
      url = ImgproxyUrl.thumbnail(source, width: 100, height: 100)

      encoded = Base64.urlsafe_encode64(source, padding: false)
      path = "/rs:fill:100:100/#{encoded}"
      signature = Base64.urlsafe_encode64(
        OpenSSL::HMAC.digest("sha256", [KEY].pack("H*"), [SALT].pack("H*") + path),
        padding: false
      )

      assert_equal "https://imgproxy.example.com/#{signature}#{path}", url
    end
  end

  test "#thumbnail should encode the requested dimensions" do
    with_imgproxy_config(endpoint: "https://imgproxy.example.com", key: KEY, salt: SALT) do
      url = ImgproxyUrl.thumbnail("https://example.com/photo.jpg", width: 50, height: 80)

      assert_includes url, "/rs:fill:50:80/"
    end
  end

  test "#thumbnail should drop a trailing slash on the endpoint" do
    with_imgproxy_config(endpoint: "https://imgproxy.example.com/", key: KEY, salt: SALT) do
      url = ImgproxyUrl.thumbnail("https://example.com/photo.jpg", width: 100, height: 100)

      assert_not_includes url, "com//"
    end
  end

  test "#thumbnail should return the source url when imgproxy is not configured" do
    with_imgproxy_config(nil) do
      source = "https://example.com/photo.jpg"
      assert_equal source, ImgproxyUrl.thumbnail(source, width: 100, height: 100)
    end
  end

  test "#thumbnail should return the source url when the key is missing" do
    with_imgproxy_config(endpoint: "https://imgproxy.example.com", salt: SALT) do
      source = "https://example.com/photo.jpg"
      assert_equal source, ImgproxyUrl.thumbnail(source, width: 100, height: 100)
    end
  end

  test "#thumbnail should return an empty string for a blank source" do
    with_imgproxy_config(endpoint: "https://imgproxy.example.com", key: KEY, salt: SALT) do
      assert_equal "", ImgproxyUrl.thumbnail(nil, width: 100, height: 100)
    end
  end

  test "#preview_srcset should offer 1x and 2x thumbnails for HiDPI displays" do
    size = ImgproxyUrl::THUMBNAIL_SIZE

    with_imgproxy_config(endpoint: "https://imgproxy.example.com", key: KEY, salt: SALT) do
      srcset = ImgproxyUrl.preview_srcset("https://example.com/photo.jpg")
      one_x, two_x = srcset.split(", ")

      assert_includes one_x, "/rs:fill:#{size}:#{size}/"
      assert one_x.end_with?(" 1x")
      assert_includes two_x, "/rs:fill:#{size * 2}:#{size * 2}/"
      assert two_x.end_with?(" 2x")
    end
  end
end
