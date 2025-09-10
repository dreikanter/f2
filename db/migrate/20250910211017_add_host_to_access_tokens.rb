class AddHostToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :access_tokens, :host, :string, null: false, default: "https://freefeed.net"
  end
end
