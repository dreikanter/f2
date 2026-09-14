module LlmModelsHelper
  def llm_models_refresh
    @llm_models_refresh ||= SolidQueue::Job.where(class_name: RefreshLlmModelsJob.name).order(id: :desc).first
  end

  def llm_models_refreshing?
    llm_models_refresh.present? && !llm_models_refresh.finished? && !llm_models_refresh.failed?
  end

  def llm_models_refreshed_at
    SolidQueue::Job.where(class_name: RefreshLlmModelsJob.name).finished.maximum(:finished_at)
  end
end
