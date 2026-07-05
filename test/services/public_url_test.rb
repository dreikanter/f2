require "test_helper"

class PublicUrlTest < ActiveSupport::TestCase
  test ".safe? should accept absolute public http and https URLs" do
    assert PublicUrl.safe?("https://example.com/path?q=1")
    assert PublicUrl.safe?("http://example.com")
    assert PublicUrl.safe?("https://cdn.example.com/a/b/c.png")
    assert PublicUrl.safe?("  https://example.com/with-space  ")
  end

  test ".safe? should reject non-http schemes" do
    assert_not PublicUrl.safe?("ftp://example.com")
    assert_not PublicUrl.safe?("file:///etc/passwd")
    assert_not PublicUrl.safe?("javascript:alert(1)")
  end

  test ".safe? should reject non-URLs and blanks" do
    assert_not PublicUrl.safe?("/proc/self/environ")
    assert_not PublicUrl.safe?("not a url")
    assert_not PublicUrl.safe?("")
    assert_not PublicUrl.safe?(nil)
  end

  test ".safe? should reject URLs carrying credentials" do
    assert_not PublicUrl.safe?("https://user:pass@example.com/")
  end

  test ".safe? should reject localhost and private/link-local hosts" do
    %w[
      http://localhost/x http://app.localhost/x http://127.0.0.1/ http://10.1.2.3/
      http://192.168.0.1/ http://172.16.5.5/ http://169.254.169.254/latest/meta-data/
      http://[::1]/ http://100.64.1.1/ http://0.0.0.0/
    ].each do |url|
      assert_not PublicUrl.safe?(url), "expected #{url} to be refused"
    end
  end

  test ".safe? should reject encoded loopback literals that resolve past a naive string check" do
    # These all resolve to 127.0.0.1 / 0.0.0.0 through the client's resolver.
    %w[
      http://2130706433/ http://0x7f000001/ http://0177.0.0.1/ http://0/
      http://[::ffff:127.0.0.1]/ http://127.0.0.1./ http://[::]/
    ].each do |url|
      assert_not PublicUrl.safe?(url), "expected #{url} to be refused"
    end
  end

  test ".safe? should allow public address literals" do
    assert PublicUrl.safe?("https://93.184.216.34/ok.png")
  end

  test ".safe? should allow public hosts that merely contain private-looking substrings" do
    assert PublicUrl.safe?("https://10.example.com/")
    assert PublicUrl.safe?("https://localhost.example.com/")
  end
end
