# Existing tokens predate the column, so they start with an empty list: their
# real scopes are unknown until something re-reads them, which
# TokenScopesRefreshJob does. Seeding a guess here would either gate a capable
# token or clear the gate for one that FreeFeed refuses.
class AddScopesToAccessTokens < ActiveRecord::Migration[8.0]
  def up
    add_column :access_tokens, :scopes, :string, array: true, null: false, default: []
  end

  def down
    remove_column :access_tokens, :scopes
  end
end
