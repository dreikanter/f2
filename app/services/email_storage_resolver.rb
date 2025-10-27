module EmailStorageResolver
  @instances = {}

  def self.resolve(adapter_name)
    adapter_name ||= :file_system
    @instances[adapter_name] ||= create_instance(adapter_name)
  end

  def self.create_instance(adapter_name)
    case adapter_name
    when :file_system
      FileSystemEmailStorage.new
    when :in_memory
      InMemoryEmailStorage.new
    else
      raise ArgumentError, "Unknown email storage adapter: #{adapter_name}"
    end
  end

  def self.clear_instances
    @instances.clear
  end
end
