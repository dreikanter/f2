class CreateInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :invites, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :created_by_user, null: false, foreign_key: { to_table: :users }
      t.references :invited_user, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
