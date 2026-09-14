FactoryBot.define do
  factory :llm_model, class: "RubyLLM::ActiveRecord::Model" do
    sequence(:model_id) { |n| "model-#{n}" }
    name { model_id }
    provider { "openai" }
    modalities { { "input" => ["text"], "output" => ["text"] } }
    capabilities { [] }
  end
end
