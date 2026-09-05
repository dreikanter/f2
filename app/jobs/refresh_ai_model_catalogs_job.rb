class RefreshAiModelCatalogsJob < ApplicationJob
  queue_as :default

  def perform
    AiCredential.active.find_each(&:refresh_models_async)
  end
end
