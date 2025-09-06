class CreateAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :access_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.integer :status, null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :access_tokens, [:user_id, :name], unique: true
  end
end
