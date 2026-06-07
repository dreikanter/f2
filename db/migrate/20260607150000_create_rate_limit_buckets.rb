class CreateRateLimitBuckets < ActiveRecord::Migration[8.2]
  def change
    create_table :rate_limit_buckets do |t|
      t.string :key, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :blocked_until

      t.timestamps
    end

    add_index :rate_limit_buckets, :key, unique: true
  end
end
