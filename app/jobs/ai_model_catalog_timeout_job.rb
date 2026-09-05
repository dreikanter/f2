class AiModelCatalogTimeoutJob < ApplicationJob
  queue_as :timeouts

  def perform(run)
    run.timeout!
  end
end
