class Admin::LlmChatsController < ApplicationController
  include Pagination

  def index
    authorize [:admin, LlmChat]
    @chats = paginate_scope
  end

  def show
    authorize [:admin, LlmChat]
    @chat = policy_scope([:admin, LlmChat]).find(params[:id])
    @messages = @chat.messages.includes(:ruby_llm_tool_calls).order(:created_at, :id)
    @usages = LlmUsageReport.new(chats: LlmChat.where(id: @chat.id)).usages.includes(:message).order(:created_at, :id)
  end

  private

  def pagination_scope
    policy_scope([:admin, LlmChat]).includes(:user).order(created_at: :desc, id: :desc)
  end
end
