class CreateFeeds < ActiveRecord::Migration[8.0]
  def change
    create_table :feeds do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :cron_expression, null: false
      t.string :loader, null: false
      t.string :processor, null: false
      t.string :normalizer, null: false
      t.datetime :import_after
      t.integer :state, null: false, default: 0
      t.string :description, null: false, default: ""

      t.timestamps
    end
  end
end
