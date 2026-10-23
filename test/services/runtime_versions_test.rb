require "test_helper"
require "tempfile"

class RuntimeVersionsTest < ActiveSupport::TestCase
  test "#call should report running software and the connected PostgreSQL server" do
    versions = RuntimeVersions.new.call

    assert_equal RUBY_VERSION, versions[:ruby]
    assert_equal Bundler::VERSION, versions[:bundler]
    assert_equal Rails.version, versions[:rails]
    assert_equal ApplicationRecord.connection.select_value("SHOW server_version"), versions[:postgresql]
    assert_match(/\A\d+\.\d+/, versions[:postgresql])
  end

  test "#call should read the distribution name and version without executing shell content" do
    with_os_release("NAME=Debian\nPRETTY_NAME=\"Debian GNU/Linux 13 (trixie) $(uname)\"\n") do |versions|
      assert_equal "Debian GNU/Linux 13 (trixie) $(uname)", versions[:operating_system]
    end
  end

  test "#call should accept unquoted and single quoted distribution names" do
    ["Alpine Linux v3.22", "'Alpine Linux v3.22'"].each do |value|
      with_os_release("PRETTY_NAME=#{value}\n") do |versions|
        assert_equal "Alpine Linux v3.22", versions[:operating_system]
      end
    end
  end

  test "#call should show unknown when the distribution name is absent or empty" do
    ["NAME=Debian\n", "PRETTY_NAME=\"\"\n"].each do |content|
      with_os_release(content) do |versions|
        assert_equal "Unknown", versions[:operating_system]
      end
    end
  end

  test "#call should tolerate systems without os release" do
    versions = RuntimeVersions.new(os_release_path: Rails.root.join("tmp/missing-os-release")).call

    assert_equal "Unknown", versions[:operating_system]
  end

  private

  def with_os_release(content)
    Tempfile.create("os-release") do |file|
      file.write(content)
      file.flush
      yield RuntimeVersions.new(os_release_path: file.path).call
    end
  end
end
