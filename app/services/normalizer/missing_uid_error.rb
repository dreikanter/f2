module Normalizer
  # Raised when a normalizer returns a Post with a blank uid. The
  # dedup workflow needs a stable per-source identifier (FR-020); a
  # missing one is a programming error in the normalizer.
  class MissingUidError < StandardError; end
end
