require "test_helper"

class LlmChatTimeoutJobTest < ActiveJob::TestCase
  test "#perform should interrupt an overdue chat even if execution never started" do
    chat = create(:llm_chat)

    travel_to chat.deadline_at, with_usec: true do
      LlmChatTimeoutJob.perform_now(chat.id)

      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal Time.current, chat.finished_at
      assert_empty chat.ruby_llm_usages

      travel 1.second
      assert_no_changes -> { chat.reload.attributes } do
        LlmChatTimeoutJob.perform_now(chat.id)
      end
    end
  end

  test "#perform should leave a chat running before its deadline" do
    chat = create(:llm_chat)

    assert_no_changes -> { chat.reload.attributes } do
      LlmChatTimeoutJob.perform_now(chat.id)
    end
  end

  test "#perform should preserve an outcome settled before the deadline" do
    chat = create(:llm_chat)
    chat.finish!(status: :succeeded)

    travel_to chat.deadline_at, with_usec: true do
      assert_no_changes -> { chat.reload.attributes } do
        LlmChatTimeoutJob.perform_now(chat.id)
      end
    end
  end

  test "#perform should ignore a deleted chat" do
    chat = create(:llm_chat)
    chat.destroy!

    assert_nothing_raised { LlmChatTimeoutJob.perform_now(chat.id) }
  end
end
