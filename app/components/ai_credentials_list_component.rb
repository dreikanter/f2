class AiCredentialsListComponent < ViewComponent::Base
  def initialize(credentials:)
    @credentials = credentials
  end

  def call
    content_tag(:div, class: "space-y-4") do
      safe_join(@credentials.map { |credential| render(AiCredentialCardComponent.new(credential: credential)) })
    end
  end
end
