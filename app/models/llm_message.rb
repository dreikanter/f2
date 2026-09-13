class LlmMessage < ApplicationRecord
  acts_as_message chat_class: "LlmChat", chat_foreign_key: :llm_chat_id

  validates :role, presence: true
end
