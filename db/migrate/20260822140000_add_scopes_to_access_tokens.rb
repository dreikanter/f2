class AddScopesToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    # Nullable with no default: NULL means "unknown"
    add_column :access_tokens, :scopes, :string, array: true
  end
end
