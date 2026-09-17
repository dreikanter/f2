module LlmChatHelper
  def llm_chat_status_badge_color(status)
    case status.to_s
    when "running"
      :info
    when "succeeded"
      :success
    when "failed"
      :danger
    when "interrupted"
      :warning
    else
      :neutral
    end
  end
end
