class AiCredentialsListComponent < ListComponent
  def initialize(credentials:)
    super()
    @credentials = credentials
  end

  def before_render
    @credentials.each { |credential| with_item(AiCredentialListItemComponent.new(credential: credential)) }
  end
end
