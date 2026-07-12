class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # PKs are UUIDv7, which is time-ordered, so ordering by id is chronological.
  # Make that explicit for finder methods (.first/.last, batching) and Postgres.
  self.implicit_order_column = "id"
end
