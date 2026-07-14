module IdentifierHelper
  UUID_SUFFIX_LENGTH = 5

  def short_ref(value)
    value.to_s.last(UUID_SUFFIX_LENGTH)
  end
end
