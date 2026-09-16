FactoryBot.define do
  factory :ruby_llm_usage, class: "RubyLLM::ActiveRecord::Usage" do
    association :chat, factory: :llm_chat
    operation { "chat" }
    provider { "openai" }
    model { "gpt-5-nano" }
    status { "succeeded" }
    input_tokens { 1_000 }
    output_tokens { 500 }
    total_cost { BigDecimal("0.03") }
  end
end
