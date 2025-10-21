class CreateFeedMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_metrics do |t|
      t.references :feed, null: false, foreign_key: true, index: false
      t.date :date, null: false

      t.integer :posts_count, default: 0, null: false
      t.integer :invalid_posts_count, default: 0, null: false

      t.timestamps

      t.index [:feed_id, :date], unique: true
      t.index :date
    end
  end
end
