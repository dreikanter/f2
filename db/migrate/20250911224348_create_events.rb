class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :type, null: false
      t.integer :level, null: false, default: 1
      t.text :message, null: false, default: ''
      t.jsonb :metadata, null: false, default: {}
      t.references :user, foreign_key: true
      t.string :subject_type
      t.bigint :subject_id
      t.datetime :expires_at

      t.timestamps
    end

    add_index :events, [:type, :created_at]
    add_index :events, [:level, :created_at]
    add_index :events, [:subject_type, :subject_id]
    add_index :events, :expires_at, where: "expires_at IS NOT NULL"
  end
end
