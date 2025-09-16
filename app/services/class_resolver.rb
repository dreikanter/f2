# Resolves class names from scope and key combinations
class ClassResolver
  # @param scope [String] the module/namespace (e.g., "Loader", "Processor")
  # @param key [String] the class key (e.g., "http", "rss")
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def self.resolve(scope, key)
    new(scope, key).resolve
  end

  # @param scope [String] the module/namespace
  # @param key [String] the class key
  def initialize(scope, key)
    @scope = scope
    @key = key
  end

  # Resolves the class from scope and key
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def resolve
    class_name = build_class_name
    constantize_class(class_name)
  end

  private

  attr_reader :scope, :key

  # Builds the full class name from scope and key
  # @return [String] the full class name (e.g., "Loader::Http")
  def build_class_name
    raise ArgumentError, "Key cannot be nil or empty" if key.nil? || key.to_s.strip.empty?

    "#{scope}::#{key.to_s.camelize}"
  end

  # Attempts to constantize the class name
  # @param class_name [String] the full class name
  # @return [Class] the resolved class
  # @raise [ArgumentError] if the class cannot be found
  def constantize_class(class_name)
    class_name.constantize
  rescue NameError
    raise ArgumentError, "Unknown #{scope.downcase}: #{key}"
  end
end