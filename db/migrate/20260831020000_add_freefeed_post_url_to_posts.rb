# Persists the full published post URL instead of deriving it from the feed's
# access token host at read time, so it stays intact after the token is
# deleted. Posts published before this column existed are left blank; readers
# fall back to an unlinked post ID for those.
class AddFreefeedPostUrlToPosts < ActiveRecord::Migration[8.2]
  def change
    add_column :posts, :freefeed_post_url, :string
  end
end
