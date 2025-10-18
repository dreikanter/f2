class UpdateOnboardingSteps < ActiveRecord::Migration[8.1]
  def change
    add_reference :onboardings, :access_token, index: true, foreign_key: { on_delete: :nullify }
    add_reference :onboardings, :feed, index: true, foreign_key: { on_delete: :nullify }
    remove_column :onboardings, :current_step, :integer, default: 0, null: false
  end
end
