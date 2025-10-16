class AddStepToOnboarding < ActiveRecord::Migration[8.1]
  def change
    add_column :onboardings, :current_step, :integer, default: 0, null: false
  end
end
