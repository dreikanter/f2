module RateLimit
  # Persisted token-bucket state for one (policy, subject) pair.
  #
  # `data` holds every per-(dimension, window) bucket for the subject as
  # `{ "dimension/window" => { "t" => tokens, "r" => refilled_at_epoch } }`.
  # `blocked_until` is a server-imposed cooldown set by RateLimit.penalize.
  class Bucket < ApplicationRecord
    self.table_name = "rate_limit_buckets"
  end
end
