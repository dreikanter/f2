module LlmModelsHelper
  def llm_models_refresh
    @llm_models_refresh ||= LlmModelRefresh.current
  end

  def llm_models_refreshing?
    SolidQueue::Job.where(class_name: RefreshLlmModelsJob.name, finished_at: nil).where.missing(:failed_execution).exists?
  end

  def llm_models_refreshed_at
    llm_models_refresh.refreshed_at
  end
end
