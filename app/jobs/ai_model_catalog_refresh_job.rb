class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.fail! { run.update!(context: { error: AiModelCatalog::UNAVAILABLE_MESSAGE }) }
  end
end
