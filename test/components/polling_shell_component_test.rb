require "test_helper"
require "view_component/test_case"

class PollingShellComponentTest < ViewComponent::TestCase
  def render_shell(**options, &block)
    block ||= proc { "body" }
    render_inline(
      PollingShellComponent.new(endpoint: "/poll", content_id: "show", **options),
      &block
    )
  end

  test "#call should mount the polling controller on the host with the endpoint" do
    host = render_shell.at_css("[data-controller='polling']")

    assert_not_nil host
    assert_equal "/poll", host["data-polling-endpoint-value"]
  end

  test "#call should default cadence to the StatePolling constants" do
    host = render_shell.at_css("[data-controller='polling']")

    assert_equal StatePolling::POLLING_INTERVAL_MS.to_s, host["data-polling-interval-value"]
    assert_equal StatePolling::POLLING_MAX_POLLS.to_s, host["data-polling-max-polls-value"]
  end

  test "#call should let callers override cadence" do
    host = render_shell(interval: 5000, max_polls: 99).at_css("[data-controller='polling']")

    assert_equal "5000", host["data-polling-interval-value"]
    assert_equal "99", host["data-polling-max-polls-value"]
  end

  test "#call should default the stop condition to the standard marker" do
    host = render_shell.at_css("[data-controller='polling']")

    assert_equal "[data-polling-done]", host["data-polling-stop-condition-value"]
  end

  test "#call should wrap the body in the content container as the stream target" do
    container = render_shell(content_class: "space-y-8") { "inner" }.at_css("#show")

    assert_not_nil container
    assert_equal "inner", container.text.strip
    assert_includes container["class"], "space-y-8"
  end

  test "#call should mark the host busy by default" do
    assert_equal "true", render_shell.at_css("[data-controller='polling']")["aria-busy"]
  end

  test "#call should omit aria-busy when indicate_busy is false" do
    host = render_shell(indicate_busy: false).at_css("[data-controller='polling']")

    assert_nil host["aria-busy"]
  end

  test "#call should flag the content target only when requested" do
    assert_nil render_shell.at_css("#show")["data-polling-target"]
    assert_equal "content", render_shell(content_target: true).at_css("#show")["data-polling-target"]
  end

  test "#call should render a hidden timeout message slot" do
    result = render_inline(PollingShellComponent.new(endpoint: "/poll", content_id: "show")) do |shell|
      shell.with_timeout_message { "Taking too long" }
      "body"
    end

    timeout = result.at_css("[data-polling-target='timeoutMessage']")
    assert_not_nil timeout
    assert timeout.has_attribute?("hidden")
    assert_equal "Taking too long", timeout.text.strip
  end

  test "#call should omit the timeout container without the slot" do
    assert_nil render_shell.at_css("[data-polling-target='timeoutMessage']")
  end
end
