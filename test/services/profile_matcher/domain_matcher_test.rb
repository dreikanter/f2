require "test_helper"

class ProfileMatcher::DomainMatcherTest < ActiveSupport::TestCase
  def declared_class
    @declared_class ||= Class.new(ProfileMatcher::DomainMatcher) do
      def self.name
        "ProfileMatcher::SampleProfileMatcher"
      end

      match_specificity 100

      match_domains "example.com", "example.net"
    end
  end

  def undeclared_class
    @undeclared_class ||= Class.new(ProfileMatcher::DomainMatcher) do
      def self.name
        "ProfileMatcher::UndeclaredProfileMatcher"
      end
    end
  end

  def matcher(url)
    declared_class.new(url)
  end

  test ".match_domains should expand each domain into bare and www hosts" do
    assert_equal %w[example.com www.example.com example.net www.example.net], declared_class.hosts
  end

  test ".match_domains should reject an empty domain list" do
    assert_raises(ArgumentError) { Class.new(ProfileMatcher::DomainMatcher).match_domains }
  end

  test ".hosts should raise NotImplementedError when no domains are declared" do
    error = assert_raises(NotImplementedError) { undeclared_class.hosts }
    assert_includes error.message, "must declare its domains via match_domains"
  end

  test "#match? should match every declared domain" do
    assert matcher("https://example.com/feed.xml").match?
    assert matcher("https://www.example.com/feed.xml").match?
    assert matcher("https://example.net/feed.xml").match?
    assert matcher("https://www.example.net/feed.xml").match?
  end

  test "#match? should not match other subdomains" do
    assert_not matcher("https://media.example.com/feed.xml").match?
  end

  test "#match? should not match undeclared hosts" do
    assert_not matcher("https://notexample.com/feed.xml").match?
  end

  test "#match? should not match declared domains appearing only in the path" do
    assert_not matcher("https://other.test/example.com/feed.xml").match?
  end

  test "#match? should handle blank inputs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end

  test "#match? should raise error for invalid URLs" do
    assert_raises(URI::InvalidURIError) { matcher("not a url").match? }
  end
end
