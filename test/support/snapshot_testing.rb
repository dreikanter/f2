module SnapshotTesting
  def assert_matches_snapshot(actual_data, snapshot:)
    full_path = Rails.root.join("test/fixtures/files", snapshot)
    actual_json = JSON.pretty_generate(actual_data)

    if ENV["UPDATE_SNAPSHOTS"]
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, actual_json + "\n")
      skip "Generated snapshot: #{snapshot}"
      return
    end

    if File.exist?(full_path)
      expected = File.read(full_path)
      assert_equal expected, actual_json + "\n", "Snapshot mismatch for #{snapshot}\nRun with UPDATE_SNAPSHOTS=1 to update snapshots"
    else
      flunk "missing snapshot; run with UPDATE_SNAPSHOTS=1 to regenerate"
    end
  end
end
