# Resolves class names from scope and key combinations
module ClassResolver
  # @param scope [String] the module/namespace (e.g., "Loader", "Processor")
  # @param key [String] the class key (e.g., "http", "rss")
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def self.resolve(scope, key)
    raise ArgumentError, "Key cannot be nil or empty" if key.nil? || key.to_s.strip.empty?

    # Add scope suffix if not already present
    key_with_suffix = key.to_s.end_with?("_#{scope.downcase}") ? key.to_s : "#{key}_#{scope.downcase}"
    class_name = "#{scope}::#{key_with_suffix.camelize}"
    class_name.constantize
  rescue NameError
    raise ArgumentError, "Unknown #{scope.downcase}: #{key}"
  end
end
