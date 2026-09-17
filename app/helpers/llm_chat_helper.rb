module LlmChatHelper
  LLM_MESSAGE_TITLES = {
    "system" => "System instructions",
    "developer" => "Developer instructions",
    "user" => "Request",
    "assistant" => "AI response",
    "tool" => "Tool result"
  }.freeze

  def llm_message_title(role)
    LLM_MESSAGE_TITLES.fetch(role) { "#{role.humanize} message" }
  end

  def format_llm_message_content(content)
    return content if content.blank?

    JSON.pretty_generate(JSON.parse(content))
  rescue JSON::ParserError
    content
  end

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
