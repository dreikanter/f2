# Resolves class names from scope and key combinations
module ClassResolver
  # @param scope [String] the module/namespace (e.g., "Loader", "Processor")
  # @param key [String] the class key (e.g., "http", "rss")
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def self.resolve(scope, key)
    raise ArgumentError, "Key cannot be nil or empty" if key.nil? || key.to_s.strip.empty?

    key_with_suffix = "#{key}_#{scope.to_s.underscore}"
    class_name = "#{scope}::#{key_with_suffix.classify}"
    class_name.constantize
  rescue NameError
    raise ArgumentError, "Can not resolve class #{class_name}"
  end
end
