class CreateFeedProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_profiles do |t|
      t.string :name, null: false
      t.string :loader, null: false
      t.string :processor, null: false
      t.string :normalizer, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :feed_profiles, :name, unique: true
  end
end
