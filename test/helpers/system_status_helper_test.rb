require "test_helper"

class SystemStatusHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "#email_delivery_status should show configured Resend without exposing its key" do
    with_email_delivery(:resend) do
      Resend.stub(:api_key, "secret-api-key") do
        assert_equal "Resend configured", email_delivery_status
      end
    end
  end

  test "#email_delivery_status should identify a missing Resend key" do
    with_email_delivery(:resend) do
      Resend.stub(:api_key, " ") do
        assert_equal "Resend not configured: missing API key", email_delivery_status
      end
    end
  end

  test "#email_delivery_status should identify a missing sender" do
    with_email_delivery(:resend) do
      Resend.stub(:api_key, "secret-api-key") do
        ApplicationMailer.stub(:default_params, { from: nil }) do
          assert_equal "Resend not configured: missing From address", email_delivery_status
        end
      end
    end
  end

  test "#email_delivery_status should prioritize disabled delivery" do
    with_email_delivery(:resend, enabled: false) do
      assert_equal "Disabled", email_delivery_status
    end
  end

  test "#email_delivery_status should explain local file delivery" do
    with_email_delivery(:file) do
      assert_equal "Saved to files; emails are not sent", email_delivery_status
    end
  end

  test "#email_delivery_status should explain test delivery" do
    with_email_delivery(:test) do
      assert_equal "Test mode; emails are not sent", email_delivery_status
    end
  end

  test "#email_delivery_status should avoid claiming unsupported methods are configured" do
    with_email_delivery(:smtp) do
      assert_equal "Smtp delivery; configuration not checked", email_delivery_status
    end
  end

  test "#environment_badge should render production as danger" do
    result = environment_badge("production")

    assert_includes result, "production"
    assert_includes result, "bg-danger-subtle"
  end

  test "#environment_badge should render staging as warning" do
    result = environment_badge("staging")

    assert_includes result, "staging"
    assert_includes result, "bg-warning-subtle"
  end

  test "#environment_badge should render development as success" do
    result = environment_badge("development")

    assert_includes result, "development"
    assert_includes result, "bg-success-subtle"
  end

  test "#environment_badge should render unknown environments as neutral" do
    result = environment_badge("test")

    assert_includes result, "test"
    assert_includes result, "bg-surface-muted"
  end

  test "#revision_commit_link should link the short hash to the commit page" do
    result = revision_commit_link("0123456", "0123456789abcdef")

    assert_includes result, "#{Feeder::GITHUB_REPO_URL}/commit/0123456789abcdef"
    assert_includes result, "<code"
    assert_includes result, "0123456"
  end

  test "#revision_commit_link should fall back to the short hash without a full revision" do
    result = revision_commit_link("0123456", nil)

    assert_includes result, "#{Feeder::GITHUB_REPO_URL}/commit/0123456"
  end

  private

  def with_email_delivery(method, enabled: true, &block)
    ApplicationMailer.stub(:perform_deliveries, enabled) do
      ApplicationMailer.stub(:delivery_method, method, &block)
    end
  end
end
