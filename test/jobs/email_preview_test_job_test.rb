require "test_helper"

class EmailPreviewTestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup { ActionMailer::Base.deliveries.clear }

  EmailPreview::CATALOG.each do |preview|
    test "#perform should deliver #{preview[:id]} to the recipient" do
      assert_emails 1 do
        EmailPreviewTestJob.perform_now(preview[:id], "dev@example.com")
      end

      assert_equal ["dev@example.com"], ActionMailer::Base.deliveries.last.to
    end
  end

  test "#perform should not register an event for the sample recipient" do
    assert_no_difference -> { Event.count } do
      EmailPreviewTestJob.perform_now("passwords_mailer-reset", "dev@example.com")
    end
  end

  test "#perform should ignore an unknown preview id" do
    assert_no_emails do
      assert_nothing_raised do
        EmailPreviewTestJob.perform_now("nope", "dev@example.com")
      end
    end
  end

  test "#perform should reset sample_mode afterward" do
    EmailPreviewTestJob.perform_now("passwords_mailer-reset", "dev@example.com")

    assert_not ApplicationMailer.sample_mode?
  end
end
