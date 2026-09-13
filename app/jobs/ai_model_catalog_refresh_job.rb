class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  def perform(run)
    AiModelCatalogRefresh.new(run).call
  end
end
