class Development::LlmModelsController < ApplicationController
  def show
    authorize [:development, :llm_model], :show?
    @refresh = LlmModelRefresh.current
    @providers = LlmModels.counts_by_provider
  end
end
