class UpdateOnboardingSteps < ActiveRecord::Migration[8.1]
  def change
    remove_column :onboardings, :current_step, :integer, default: 0, null: false
    add_reference :onboardings, :access_token, foreign_key: true
    add_reference :onboardings, :feed, foreign_key: true
  end
end
