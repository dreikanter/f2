require "test_helper"

class Development::SentEmailsPurgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    email_storage.purge
    sign_in_as(create(:user, :dev))
  end

  def email_storage
    EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter)
  end

  test "#destroy should empty the mailbox" do
    store_email
    assert_equal 1, email_storage.list.count

    delete development_sent_emails_purge_path

    assert_redirected_to development_sent_emails_path
    assert_equal "All emails purged", flash[:success]
    assert_equal 0, email_storage.list.count
  end

  test "#destroy should report a storage failure instead of raising" do
    email_storage.stub(:purge, -> { raise "Purge failed" }) do
      delete development_sent_emails_purge_path

      assert_redirected_to development_sent_emails_path
      assert_equal "Failed to purge emails: Purge failed", flash[:alert]
    end
  end

  test "#destroy should require dev permission" do
    sign_in_as(create(:user))

    delete development_sent_emails_purge_path

    assert_response :redirect
  end

  private

  def store_email
    email_storage.save_email(
      metadata: { "subject" => "Test Subject", "timestamp" => Time.current },
      text_content: "Test email body"
    )
  end
end
