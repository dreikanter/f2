class Onboarding < ApplicationRecord
  belongs_to :user

  enum :current_step, { introduction: 0, token: 1, feed: 2, schedule: 3, finalization: 4 }

  def next_step
    return nil if finalization?

    steps = ordered_steps
    current_index = steps.index(current_step)
    return nil if current_index.nil? || current_index >= steps.length - 1

    steps[current_index + 1]
  end

  def step_number
    current_index = ordered_steps.index(current_step)
    current_index ? current_index + 1 : nil
  end

  def total_steps
    self.class.current_steps.length
  end

  def first_step?
    introduction?
  end

  def last_step?
    finalization?
  end

  private

  def ordered_steps
    self.class.current_steps.keys.map(&:to_s)
  end
end
