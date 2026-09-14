module LlmModelsHelper
  def llm_models_refresh
    @llm_models_refresh ||= LlmModelRefresh.current
  end

  def llm_models_refreshed_at
    llm_models_refresh.refreshed_at
  end
end
