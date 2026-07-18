require "test_helper"

class WebhookLogScrubbingTest < ActiveSupport::TestCase
  LogEvent = Struct.new(:message, :payload)

  test ".scrub should mask the token in a request path" do
    scrubbed = WebhookLogScrubbing.scrub("Started POST \"/hooks/abc-DEF_123\" for 127.0.0.1")

    assert_equal "Started POST \"/hooks/[FILTERED]\" for 127.0.0.1", scrubbed
  end

  test ".scrub should leave other paths alone" do
    assert_equal "GET /feeds/42", WebhookLogScrubbing.scrub("GET /feeds/42")
  end

  test ".call should scrub the message and the payload path" do
    log = LogEvent.new("POST /hooks/secret", { path: "/hooks/secret?x=1", controller: "WebhookPostsController" })

    WebhookLogScrubbing.call(log)

    assert_equal "POST /hooks/[FILTERED]", log.message
    assert_equal "/hooks/[FILTERED]?x=1", log.payload[:path]
  end

  test ".call should tolerate a log event without message or payload" do
    log = LogEvent.new(nil, nil)

    WebhookLogScrubbing.call(log)

    assert_nil log.message
  end
end
