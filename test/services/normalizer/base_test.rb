require "test_helper"

class Normalizer::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed_entry = create(:feed_entry)

    assert_nothing_raised do
      Normalizer::Base.new(feed_entry)
    end
  end

  test "should raise NotImplementedError for build_post method" do
    feed_entry = create(:feed_entry)
    normalizer = Normalizer::Base.new(feed_entry)

    assert_raises(NotImplementedError) do
      normalizer.send(:build_post)
    end
  end

  test "should return empty array for validate_post method" do
    feed_entry = create(:feed_entry)
    normalizer = Normalizer::Base.new(feed_entry)
    post = build(:post)

    result = normalizer.send(:validate_post, post)
    assert_equal [], result
  end
end
