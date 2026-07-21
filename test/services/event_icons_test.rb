require "test_helper"

class EventIconsTest < ActiveSupport::TestCase
  test "#icon_for should return the configured icon for a mapped type" do
    assert_equal "refresh-ccw", EventIcons.icon_for("feed_refresh")
  end

  test "#icon_for should return nil for an unmapped type" do
    assert_nil EventIcons.icon_for("some_unmapped_type")
  end

  test "#icon_for should ignore entries naming an unbundled icon" do
    EventIcons.stub(:table, { "custom_event" => "no-such-icon" }) do
      assert_nil EventIcons.icon_for("custom_event")
    end
  end

  test "every configured icon should be in the bundled icon set" do
    YAML.safe_load(File.read(EventIcons::PATH)).each do |type, name|
      assert ApplicationHelper::ICONS.key?(name), "#{type} names unbundled icon #{name}"
    end
  end
end
