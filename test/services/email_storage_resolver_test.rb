require "test_helper"

class EmailStorageResolverTest < ActiveSupport::TestCase
  teardown do
    EmailStorageResolver.clear_instances
  end

  test ".resolve returns FileSystemEmailStorage for :file_system" do
    storage = EmailStorageResolver.resolve(:file_system)
    assert_instance_of FileSystemEmailStorage, storage
  end

  test ".resolve returns InMemoryEmailStorage for :in_memory" do
    storage = EmailStorageResolver.resolve(:in_memory)
    assert_instance_of InMemoryEmailStorage, storage
  end

  test ".resolve returns FileSystemEmailStorage for nil" do
    storage = EmailStorageResolver.resolve(nil)
    assert_instance_of FileSystemEmailStorage, storage
  end

  test ".resolve raises ArgumentError for unknown adapter" do
    error = assert_raises(ArgumentError) do
      EmailStorageResolver.resolve(:unknown)
    end
    assert_equal "Unknown email storage adapter: unknown", error.message
  end

  test ".resolve returns same instance for same adapter (singleton)" do
    storage1 = EmailStorageResolver.resolve(:in_memory)
    storage2 = EmailStorageResolver.resolve(:in_memory)
    assert_same storage1, storage2
  end

  test ".resolve returns different instances for different adapters" do
    storage1 = EmailStorageResolver.resolve(:file_system)
    storage2 = EmailStorageResolver.resolve(:in_memory)
    refute_equal storage1.class, storage2.class
  end

  test ".clear_instances clears cached instances" do
    storage1 = EmailStorageResolver.resolve(:in_memory)
    EmailStorageResolver.clear_instances
    storage2 = EmailStorageResolver.resolve(:in_memory)
    refute_same storage1, storage2
  end
end
