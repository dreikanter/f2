class AddScopesToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    # Nullable with no default: NULL means "unknown" (validated before this
    # column existed, or a session token, which has no scopes to speak of) and
    # is deliberately distinct from an app token that holds none.
    add_column :access_tokens, :scopes, :string, array: true
  end
end
