class CreateSearchCredentials < ActiveRecord::Migration[8.2]
  def change
    create_table :search_credentials, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true, index: false
      t.string :provider, null: false
      t.string :display_name, null: false
      t.jsonb :credential_data, default: {}, null: false
      t.integer :state, default: 0, null: false
      t.datetime :last_validated_at
      t.text :last_error
      t.timestamps

      t.index [:user_id, :provider, :display_name],
              unique: true,
              name: "index_search_credentials_on_owner_provider_name"
      t.index [:user_id, :state]
    end

    add_reference :users,
                  :default_search_credential,
                  type: :uuid,
                  foreign_key: { to_table: :search_credentials, on_delete: :nullify }
  end
end
