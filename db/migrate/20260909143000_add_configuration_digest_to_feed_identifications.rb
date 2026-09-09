class AddConfigurationDigestToFeedIdentifications < ActiveRecord::Migration[8.2]
  def change
    add_column :feed_identifications, :configuration_digest, :string
  end
end
