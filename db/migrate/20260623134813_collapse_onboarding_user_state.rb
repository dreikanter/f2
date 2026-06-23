class CollapseOnboardingUserState < ActiveRecord::Migration[8.2]
  # The onboarding state was redundant: nothing promoted users out of it and it
  # behaved exactly like active at every gate. Fold existing onboarding users
  # into active so confirmed accounts are consistent — and so password reset,
  # which only looks up active accounts, works for them.
  def up
    execute("UPDATE users SET state = 2 WHERE state = 1")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
