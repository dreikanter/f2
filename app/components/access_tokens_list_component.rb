class AccessTokensListComponent < ViewComponent::Base
  def initialize(access_tokens:)
    @access_tokens = access_tokens
  end

  def call
    return "" if @access_tokens.empty?

    content_tag(:div, class: "space-y-4") do
      safe_join(@access_tokens.map { |at| render(AccessTokenCardComponent.new(access_token: at)) })
    end
  end
end
