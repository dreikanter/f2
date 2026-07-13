class SearchCredentialsListComponent < ListComponent
  def initialize(credentials:)
    super()
    @credentials = credentials
  end

  def before_render
    @credentials.each do |credential|
      with_item(SearchCredentialListItemComponent.new(credential: credential))
    end
  end
end
