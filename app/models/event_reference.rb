class EventReference < ApplicationRecord
  belongs_to :event
  belongs_to :reference, polymorphic: true

  # Resolves the referenced records for a set of references, eager-loading the
  # polymorphic targets and dropping any that have since been deleted.
  def self.referenced_records
    includes(:reference).filter_map(&:reference)
  end
end
