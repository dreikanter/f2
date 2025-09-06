class TokenValidationService
  def self.validate_token(token_string)
    return false if token_string.blank?

    access_token = find_token_by_value(token_string)
    return false unless access_token&.active?

    access_token.touch_last_used!
    access_token.user
  end

  private

  def self.find_token_by_value(token_string)
    AccessToken.active.find_each do |token|
      return token if token.authenticate(token_string)
    end
    nil
  end
end
