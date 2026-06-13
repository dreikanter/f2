class AddFreefeedUserIdToAccessTokens < ActiveRecord::Migration[8.2]
  def up
    add_column :access_tokens, :freefeed_user_id, :string
    add_index :access_tokens, :freefeed_user_id

    # Backfill from the validation detail we already persist, so existing active
    # tokens get an account-scoped rate-limit subject without re-validating.
    execute(<<~SQL.squish)
      UPDATE access_tokens
      SET freefeed_user_id = access_token_details.data -> 'user_info' ->> 'id'
      FROM access_token_details
      WHERE access_token_details.access_token_id = access_tokens.id
        AND access_token_details.data -> 'user_info' ->> 'id' IS NOT NULL
    SQL
  end

  def down
    remove_index :access_tokens, :freefeed_user_id
    remove_column :access_tokens, :freefeed_user_id
  end
end
