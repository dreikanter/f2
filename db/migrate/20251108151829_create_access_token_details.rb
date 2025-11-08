class CreateAccessTokenDetails < ActiveRecord::Migration[8.2]
  def change
    create_table :access_token_details do |t|
      t.references :access_token, null: false, foreign_key: true, index: {unique: true}
      t.jsonb :data, null: false, default: {}
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :access_token_details, :expires_at
  end
end
