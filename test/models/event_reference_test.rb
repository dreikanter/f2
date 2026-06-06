require "test_helper"

class EventReferenceTest < ActiveSupport::TestCase
  def event
    @event ||= create(:event)
  end

  def post
    @post ||= create(:post)
  end

  test "should create reference linking an event to a record" do
    reference = EventReference.create!(event: event, reference: post)

    assert_equal event, reference.event
    assert_equal post, reference.reference
    assert_equal "Post", reference.reference_type
    assert_equal post.id, reference.reference_id
  end

  test "should require an event" do
    reference = EventReference.new(reference: post)

    assert_not reference.valid?
    assert reference.errors.of_kind?(:event, :blank)
  end

  test "should require a reference" do
    reference = EventReference.new(event: event)

    assert_not reference.valid?
    assert reference.errors.of_kind?(:reference, :blank)
  end

  test "should survive deletion of the referenced record" do
    reference = EventReference.create!(event: event, reference: post)
    post.destroy!

    reference.reload

    assert_equal "Post", reference.reference_type
    assert_nil reference.reference
  end
end
