require "test_helper"

class EmailPreviewTest < ActiveSupport::TestCase
  test "#all should return the catalog" do
    assert_equal EmailPreview::CATALOG, EmailPreview.all
  end

  test "#find should return the matching catalog entry" do
    assert_equal "Password Reset", EmailPreview.find("passwords_mailer-reset")[:label]
  end

  test "#find should return nil for an unknown id" do
    assert_nil EmailPreview.find("nope")
  end

  test "#delivery should return nil for an unknown id" do
    assert_nil EmailPreview.delivery("nope")
  end

  EmailPreview::CATALOG.each do |preview|
    test "#delivery should build a message for #{preview[:id]}" do
      assert_kind_of ActionMailer::MessageDelivery, EmailPreview.delivery(preview[:id])
    end
  end

  test "#sample_user should build an unpersisted user with sample addresses" do
    user = EmailPreview.sample_user

    assert_not user.persisted?
    assert_equal "preview@example.com", user.email_address
    assert_equal "new.preview@example.com", user.unconfirmed_email
  end
end
