class Onboarding < ApplicationRecord
  belongs_to :user

  enum :current_step, { intro: 0, token: 1, feed: 2, schedule: 3, outro: 4 }

  def next_step
    step_keys[current_step_index + 1]
  end

  def current_step_number
    current_step_index ? current_step_index + 1 : nil
  end

  def total_steps
    self.class.current_steps.length
  end

  def first_step?
    intro?
  end

  def last_step?
    outro?
  end

  private

  def step_keys
    @step_keys ||= self.class.current_steps.keys
  end

  def current_step_index
    step_keys.index(current_step.to_s)
  end
end
