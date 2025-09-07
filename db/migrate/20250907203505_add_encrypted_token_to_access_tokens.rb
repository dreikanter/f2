class AddEncryptedTokenToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :access_tokens, :encrypted_token, :text
    remove_column :access_tokens, :token_digest, :string, null: false
  end
end
