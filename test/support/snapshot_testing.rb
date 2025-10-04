module SnapshotTesting
  def assert_matches_snapshot(actual_content, snapshot:)
    full_path = Rails.root.join("test/fixtures", snapshot)

    if ENV["UPDATE_SNAPSHOTS"]
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, actual_content + "\n")
      skip "Generated snapshot: #{snapshot}"
      return
    end

    if File.exist?(full_path)
      expected = File.read(full_path)
      assert_equal expected, actual_content + "\n", "Snapshot mismatch for #{snapshot}\nRun with UPDATE_SNAPSHOTS=1 to update snapshots"
    else
      flunk "missing snapshot; run with UPDATE_SNAPSHOTS=1 to regenerate"
    end
  end

  def serialize_post(post)
    post.as_json(except: [:id, :created_at, :updated_at, :feed_id, :feed_entry_id, :freefeed_post_id])
  end
end
