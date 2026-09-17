require "test_helper"

class EventReferenceTest < ActiveSupport::TestCase
  def event
    @event ||= create(:event)
  end

  def post
    @post ||= create(:post)
  end

  test ".create! should create reference linking an event to a record" do
    reference = EventReference.create!(event: event, reference: post)

    assert_equal event, reference.event
    assert_equal post, reference.reference
    assert_equal "Post", reference.reference_type
    assert_equal post.id, reference.reference_id
  end

  test "#valid? should require an event" do
    reference = EventReference.new(reference: post)

    assert_not reference.valid?
    assert reference.errors.of_kind?(:event, :blank)
  end

  test "#valid? should require a reference" do
    reference = EventReference.new(event: event)

    assert_not reference.valid?
    assert reference.errors.of_kind?(:reference, :blank)
  end

  test "#destroy! should delete event references when the referenced post is destroyed" do
    reference = EventReference.create!(event: event, reference: post)

    post.destroy!

    assert_not EventReference.exists?(reference.id)
  end

  test "#destroy! should delete event references when the referenced chat is destroyed" do
    chat = create(:llm_chat)
    reference = EventReference.create!(event: event, reference: chat)

    chat.destroy!

    assert_not EventReference.exists?(reference.id)
  end
end
