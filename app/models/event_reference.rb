class EventReference < ApplicationRecord
  belongs_to :event
  belongs_to :reference, polymorphic: true
end
