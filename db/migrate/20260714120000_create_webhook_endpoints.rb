class CreateWebhookEndpoints < ActiveRecord::Migration[8.2]
  def change
    create_table :webhook_endpoints, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :feed, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.text :encrypted_token, null: false
      t.datetime :last_received_at
      t.integer :received_count, default: 0, null: false
      t.timestamps

      t.index :encrypted_token, unique: true
    end
  end
end
