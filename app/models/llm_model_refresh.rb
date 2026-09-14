# One shared outcome, retained independently of queue history.
class LlmModelRefresh < ApplicationRecord
  def self.current
    find_or_initialize_by(id: 1)
  end

  def failed?
    failed_at.present?
  end
end
