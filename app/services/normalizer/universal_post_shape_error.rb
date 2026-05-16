module Normalizer
  # Raised when a normalizer returns a Post missing fields the universal
  # post shape requires (see notes/profile-contracts.md §1). Programming
  # error in the normalizer — distinct from per-post content validation
  # (which records :rejected on the Post instead).
  class UniversalPostShapeError < StandardError; end
end
