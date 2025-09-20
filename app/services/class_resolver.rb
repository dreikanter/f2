# Resolves class names from scope and key combinations
module ClassResolver
  # @param scope [String] the module/namespace (e.g., "Loader", "Processor")
  # @param key [String] the class key (e.g., "http", "rss")
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def self.resolve(scope, key)
    raise ArgumentError, "Key cannot be nil or empty" if key.nil? || key.to_s.strip.empty?

    class_name = "#{scope}::#{key.to_s.camelize}"
    class_name.constantize
  rescue NameError
    raise ArgumentError, "Unknown #{scope.downcase}: #{key}"
  end
end
