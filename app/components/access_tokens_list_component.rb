class AccessTokensListComponent < ListComponent
  def initialize(access_tokens:)
    super()
    @access_tokens = access_tokens
  end

  def before_render
    @access_tokens.each { |access_token| with_item(AccessTokenListItemComponent.new(access_token: access_token)) }
  end
end
