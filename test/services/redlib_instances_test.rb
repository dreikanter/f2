require "test_helper"

class RedlibInstancesTest < ActiveSupport::TestCase
  include CacheTestHelpers

  test "#urls should keep unique public HTTPS instances" do
    directory = {
      instances: [
        { url: "https://redlib.example/" },
        { url: "https://redlib.example" },
        { onion: "http://example.onion" },
        { url: "http://insecure.example" },
        { url: "https://127.0.0.1" },
        { url: "https://user:password@example.com" },
        { url: nil }
      ]
    }
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(body: directory.to_json)

    with_memory_cache do
      assert_equal ["https://redlib.example"], RedlibInstances.new.urls
    end
  end

  test "#urls should cache the directory for one hour" do
    stub_request(:get, RedlibInstances::SOURCE_URL)
      .to_return(body: { instances: [{ url: "https://first.example" }] }.to_json)
      .then.to_return(body: { instances: [{ url: "https://second.example" }] }.to_json)

    with_memory_cache do
      assert_equal ["https://first.example"], RedlibInstances.new.urls
      assert_equal ["https://first.example"], RedlibInstances.new.urls
      assert_requested :get, RedlibInstances::SOURCE_URL, times: 1

      travel 61.minutes do
        assert_equal ["https://second.example"], RedlibInstances.new.urls
      end
    end
  end

  test "#urls should not cache a failed discovery" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(status: 503)
      .then.to_return(body: { instances: [{ url: "https://redlib.example" }] }.to_json)

    with_memory_cache do
      assert_raises(RedlibInstances::Error) { RedlibInstances.new.urls }
      assert_equal ["https://redlib.example"], RedlibInstances.new.urls
    end
  end

  test "#urls should reject invalid JSON" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(body: "<html>Unavailable</html>")

    with_memory_cache do
      assert_raises(RedlibInstances::Error) { RedlibInstances.new.urls }
    end
  end

  test "#urls should reject malformed directory data" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(body: '{"instances":{}}')

    with_memory_cache do
      assert_raises(RedlibInstances::Error) { RedlibInstances.new.urls }
    end
  end

  test "#urls should reject an empty directory" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(body: '{"instances":[]}')

    with_memory_cache do
      assert_raises(RedlibInstances::Error) { RedlibInstances.new.urls }
    end
  end

  test "#urls should wrap connection errors" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))

    with_memory_cache do
      assert_raises(RedlibInstances::Error) { RedlibInstances.new.urls }
    end
  end
end
