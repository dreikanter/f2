require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  def user
    @user ||= build(:user)
  end

  test "#wrap_delivery_behavior! should use the test backend in preview mode" do
    with_delivery_method(:resend) do
      original_api_key = Resend.api_key
      Resend.api_key = nil
      ApplicationMailer.preview_mode = true

      message = nil
      assert_nothing_raised do
        message = ProfileMailer.account_confirmation(user).message
      end

      assert_kind_of Mail::TestMailer, message.delivery_method
    ensure
      ApplicationMailer.preview_mode = false
      Resend.api_key = original_api_key
    end
  end

  test "#wrap_delivery_behavior! should use the configured backend otherwise" do
    with_delivery_method(:resend) do
      original_api_key = Resend.api_key
      Resend.api_key = "test"

      message = ProfileMailer.account_confirmation(user).message

      assert_kind_of Resend::Mailer, message.delivery_method
    ensure
      Resend.api_key = original_api_key
    end
  end

  private

  def with_delivery_method(method)
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = method
    yield
  ensure
    ActionMailer::Base.delivery_method = original
  end
end
