require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  # DSL machinery is exercised on throwaway registries so the tests don't
  # depend on the real settings' declarations.
  def build_registry(&block)
    Class.new(AppConfig).tap { |registry| registry.class_eval(&block) }
  end

  def stub_credentials(values)
    credentials = Rails.application.credentials
    original = credentials.method(:dig)
    stubbed = ->(*keys) { values.key?(keys) ? values[keys] : original.call(*keys) }

    credentials.stub(:dig, stubbed) { yield }
  end

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end

  IMGPROXY_CONFIG = {
    [:imgproxy, :endpoint] => "https://imgproxy.example.com",
    [:imgproxy, :key] => "1a2b3c4d",
    [:imgproxy, :salt] => "5e6f7a8b"
  }.freeze

  test ".setting should define a reader" do
    registry = build_registry { setting :api_key, source: -> { "secret" } }

    assert_equal "secret", registry.api_key
  end

  test ".setting should fall back to the default when the source is blank" do
    registry = build_registry { setting :timeout, source: -> { }, default: "15" }

    assert_equal "15", registry.timeout
  end

  test ".setting should normalize a present value before validation" do
    registry = build_registry do
      setting :endpoint,
        source: -> { "https://example.com///" },
        normalize: ->(value) { value.sub(%r{/+\z}, "") },
        validate: ->(value) { !value.end_with?("/") }
    end

    assert_equal "https://example.com", registry.endpoint
    assert_nothing_raised { registry.validate! }
  end

  test ".setting should not normalize an absent value" do
    registry = build_registry do
      setting :endpoint, source: -> { }, normalize: ->(_value) { raise "normalize must not run" }
    end

    assert_nil registry.endpoint
  end

  test ".setting should define a presence predicate" do
    registry = build_registry do
      setting :set_key, source: -> { "value" }
      setting :unset_key, source: -> { }
    end

    assert_predicate registry, :set_key?
    assert_not_predicate registry, :unset_key?
  end

  test ".group should define a predicate requiring every member" do
    registry = build_registry do
      setting :endpoint, source: -> { "https://example.com" }
      setting :key, source: -> { }
      group :feature, %i[endpoint key]
    end

    assert_not_predicate registry, :feature?
  end

  test "#validate! should pass when optional settings are absent" do
    registry = build_registry { setting :api_key, source: -> { } }

    assert_nothing_raised { registry.validate! }
  end

  test "#validate! should report a required setting that is missing" do
    registry = build_registry { setting :api_key, source: -> { }, required: true }

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "api_key: required in test but not set"
  end

  test "#validate! should evaluate required per environment" do
    registry = build_registry do
      setting :api_key, source: -> { }, required: -> { Rails.env.production? }
    end

    assert_nothing_raised { registry.validate! }

    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(AppConfig::ConfigurationError) { registry.validate! }
    end
  end

  test "#validate! should validate optional settings that are set" do
    registry = build_registry do
      setting :url, source: -> { "not a url" }, validate: ->(value) { value.start_with?("https://") }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "url: present but invalid"
  end

  test "#validate! should not run validation for absent settings" do
    registry = build_registry do
      setting :url, source: -> { }, validate: ->(_value) { raise "validation must not run" }
    end

    assert_nothing_raised { registry.validate! }
  end

  test "#validate! should apply the default before validation" do
    registry = build_registry do
      setting :url, source: -> { }, default: "ftp://example.com", validate: ->(value) { value.start_with?("https://") }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "url: present but invalid"
  end

  test "#validate! should aggregate every violation into a single error" do
    registry = build_registry do
      setting :first, source: -> { }, required: true
      setting :second, source: -> { "bad" }, validate: ->(_value) { false }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "first: required"
    assert_includes error.message, "second: present but invalid"
  end

  test "#validate! should report a validator that raises without echoing the value" do
    registry = build_registry do
      setting :url, source: -> { "sensitive secret value" }, validate: ->(value) { URI.parse(value).is_a?(URI::HTTP) }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "url: evaluation raised URI::InvalidURIError"
    assert_not_includes error.message, "sensitive secret value"
  end

  test "#validate! should allow a fully absent group" do
    registry = build_registry do
      setting :endpoint, source: -> { }
      setting :key, source: -> { }
      group :feature, %i[endpoint key], functional: -> { raise "must not run" }
    end

    assert_nothing_raised { registry.validate! }
  end

  test "#validate! should report a partial group" do
    registry = build_registry do
      setting :endpoint, source: -> { "https://example.com" }
      setting :key, source: -> { }
      group :feature, %i[endpoint key]
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "feature: partial configuration (missing: key)"
  end

  test "#validate! should run the functional check on a complete group" do
    ran = false
    registry = build_registry do
      setting :endpoint, source: -> { "https://example.com" }
      setting :key, source: -> { "abcd" }
      group :feature, %i[endpoint key], functional: -> { ran = true }
    end

    registry.validate!

    assert ran
  end

  test "#validate! should report a functional check failure" do
    registry = build_registry do
      setting :endpoint, source: -> { "https://example.com" }
      group :feature, %i[endpoint], functional: -> { raise "sample request failed" }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "feature: sample request failed"
  end

  test "#validate! should skip the functional check when a member is invalid" do
    registry = build_registry do
      setting :endpoint, source: -> { "bad" }, validate: ->(_value) { false }
      group :feature, %i[endpoint], functional: -> { raise "must not run" }
    end

    error = assert_raises(AppConfig::ConfigurationError) { registry.validate! }

    assert_includes error.message, "endpoint: present but invalid"
    assert_not_includes error.message, "must not run"
  end

  test "#status should map setting names to presence booleans" do
    registry = build_registry do
      setting :set_key, source: -> { "value" }
      setting :unset_key, source: -> { }
    end

    assert_equal({ set_key: true, unset_key: false }, registry.status)
  end

  test "#validate! should pass with empty credentials in test" do
    assert_nothing_raised { AppConfig.validate! }
  end

  test "#validate! should require resend credentials outside development and test" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      error = assert_raises(AppConfig::ConfigurationError) { AppConfig.validate! }

      assert_includes error.message, "resend_api_key: required in production but not set"
      assert_includes error.message, "resend_signing_secret: required in production but not set"
    end
  end

  # Pins the exact required set: a setting accidentally marked required would
  # block every production and staging deploy at the boot gate.
  test "#validate! should require nothing beyond resend credentials in production" do
    resend = {
      [:resend, :api_key] => "re_test_key",
      [:resend, :signing_secret] => "whsec_test"
    }

    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      stub_credentials(resend) do
        assert_nothing_raised { AppConfig.validate! }
      end
    end
  end

  test "#validate! should accept a complete imgproxy configuration" do
    stub_credentials(IMGPROXY_CONFIG) do
      assert_nothing_raised { AppConfig.validate! }
      assert_predicate AppConfig, :imgproxy?
    end
  end

  test "#validate! should reject a partial imgproxy configuration" do
    stub_credentials(IMGPROXY_CONFIG.except([:imgproxy, :key], [:imgproxy, :salt])) do
      error = assert_raises(AppConfig::ConfigurationError) { AppConfig.validate! }

      assert_includes error.message, "imgproxy: partial configuration (missing: imgproxy_key, imgproxy_salt)"
    end
  end

  test "#imgproxy_endpoint should strip trailing slashes" do
    stub_credentials(IMGPROXY_CONFIG.merge([:imgproxy, :endpoint] => "https://imgproxy.example.com/")) do
      assert_equal "https://imgproxy.example.com", AppConfig.imgproxy_endpoint
      assert_nothing_raised { AppConfig.validate! }
    end
  end

  test "#validate! should reject an imgproxy endpoint that is not an http url" do
    stub_credentials(IMGPROXY_CONFIG.merge([:imgproxy, :endpoint] => "imgproxy.example.com")) do
      error = assert_raises(AppConfig::ConfigurationError) { AppConfig.validate! }

      assert_includes error.message, "imgproxy_endpoint: present but invalid"
    end
  end

  test "#validate! should reject an imgproxy key that is not hex bytes" do
    stub_credentials(IMGPROXY_CONFIG.merge([:imgproxy, :key] => "abc")) do
      error = assert_raises(AppConfig::ConfigurationError) { AppConfig.validate! }

      assert_includes error.message, "imgproxy_key: present but invalid"
    end
  end

  test "#validate! should reject a malformed METRICS_URL" do
    with_env("METRICS_URL", "not a url") do
      error = assert_raises(AppConfig::ConfigurationError) { AppConfig.validate! }

      assert_includes error.message, "metrics_url: present but invalid"
    end
  end

  test "#validate! should accept a valid METRICS_URL" do
    with_env("METRICS_URL", "https://vm.example.com/api/v1/import/prometheus") do
      assert_nothing_raised { AppConfig.validate! }
    end
  end
end
