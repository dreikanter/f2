module Normalizer
  # Raised when a normalizer returns a Post with no published_at. Post
  # ordering and scheduling assume a non-null timestamp; a missing one
  # is a programming error in the normalizer.
  class MissingPublishedAtError < StandardError; end
end
