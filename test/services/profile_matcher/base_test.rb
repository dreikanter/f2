require "test_helper"

class ProfileMatcher::BaseTest < ActiveSupport::TestCase
  def declared_class
    @declared_class ||= Class.new(ProfileMatcher::Base) do
      def self.name
        "ProfileMatcher::SampleProfileMatcher"
      end

      input_shape :url
      match_specificity 42
      depends_on_ai true

      def match?
        true
      end
    end
  end

  def undeclared_class
    @undeclared_class ||= Class.new(ProfileMatcher::Base) do
      def self.name
        "ProfileMatcher::UndeclaredProfileMatcher"
      end
    end
  end

  test ".input_shape should return the declared symbol" do
    assert_equal :url, declared_class.input_shape
  end

  test ".match_specificity should return the declared integer" do
    assert_equal 42, declared_class.match_specificity
  end

  test ".depends_on_ai should return the declared boolean" do
    assert declared_class.depends_on_ai
  end

  test ".depends_on_ai should default to false when not declared" do
    quiet = Class.new(ProfileMatcher::Base) do
      def self.name
        "ProfileMatcher::QuietProfileMatcher"
      end

      input_shape :url
      match_specificity 1
    end

    assert_equal false, quiet.depends_on_ai
  end

  test ".input_shape should raise NotImplementedError when not declared" do
    error = assert_raises(NotImplementedError) { undeclared_class.input_shape }
    assert_includes error.message, "must declare input_shape"
  end

  test ".match_specificity should raise NotImplementedError when not declared" do
    error = assert_raises(NotImplementedError) { undeclared_class.match_specificity }
    assert_includes error.message, "must declare match_specificity"
  end

  test ".input_shape should reject unknown shapes" do
    klass = Class.new(ProfileMatcher::Base)
    assert_raises(ArgumentError) { klass.input_shape :twitter }
  end

  test ".match_specificity should reject non-integer values" do
    klass = Class.new(ProfileMatcher::Base)
    assert_raises(ArgumentError) { klass.match_specificity "high" }
  end

  test ".profile_key should derive from the class name" do
    assert_equal "sample", declared_class.profile_key
  end

  test "#match? should raise NotImplementedError on the base class" do
    instance = ProfileMatcher::Base.new("any input")
    assert_raises(NotImplementedError) { instance.match? }
  end

  test "#initialize should expose input and fetched_body" do
    instance = declared_class.new("https://example.com", "<rss></rss>")
    assert_equal "https://example.com", instance.input
    assert_equal "<rss></rss>", instance.fetched_body
  end

  test "#initialize should default fetched_body to nil" do
    instance = declared_class.new("https://example.com")
    assert_nil instance.fetched_body
  end
end
