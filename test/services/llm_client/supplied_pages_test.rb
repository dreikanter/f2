require "test_helper"

class LlmClient::SuppliedPagesTest < ActiveSupport::TestCase
  def budget
    @budget ||= LlmClient::ToolBudget.new
  end

  def pages
    LlmClient::SuppliedPages.new(budget: budget)
  end

  test "#fetch should cap and deduplicate supplied URLs using the shared tool allowance" do
    urls = (1..4).map { |n| "https://example.com/#{n}" }
    urls.each { |url| stub_request(:get, url).to_return(body: "<p>Content</p>") }

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      pages.fetch(([urls.first] + urls).join(" "))
    end

    assert_equal urls.first(3), result.pluck(:url)
    assert_equal 3, budget.spent
    assert_equal "Content", result.first.dig(:result, "content")
    assert_not_requested :get, urls.last
  end

  test "#fetch should refuse private URLs and redirects without turning errors into evidence" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/secret" })

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      pages.fetch("http://127.0.0.1/secret https://example.com/redirect")
    end

    assert_equal 2, result.size
    assert result.all? { |page| page[:result]["error"].present? && page[:result]["content"].nil? }
    assert_not_requested :get, "http://127.0.0.1/secret"
  end
end
