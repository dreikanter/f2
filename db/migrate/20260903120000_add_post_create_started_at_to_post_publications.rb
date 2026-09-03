# Marks that a create request was sent, so a publication resumed after a crash
# can tell "never sent" from "sent, outcome unknown".
class AddPostCreateStartedAtToPostPublications < ActiveRecord::Migration[8.2]
  def change
    add_column :post_publications, :post_create_started_at, :datetime
  end
end
