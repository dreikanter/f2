class DropOnboardings < ActiveRecord::Migration[8.0]
  def change
    drop_table :onboardings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :access_token, foreign_key: true
      t.references :feed, foreign_key: true

      t.timestamps
    end
  end
end
