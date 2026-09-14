module LlmModelsHelper
  def llm_models_refresh
    @llm_models_refresh ||= LlmModelRefresh.current
  end

  def llm_models_refreshed_at
    llm_models_refresh.refreshed_at
  end

  # @param refresh [LlmModelRefresh] shared refresh state
  # @return [String] how the most recent attempt went
  def llm_model_refresh_outcome(refresh)
    return "Failed #{short_time_ago(refresh.failed_at)} ago" if refresh.failed?
    return StatItemComponent::BLANK_VALUE if refresh.refreshed_at.nil?

    "All good"
  end

  # @param row [Hash] one entry from LlmModels.counts_by_provider
  # @return [String] listed count, with unlisted leftovers spelled out
  def llm_model_count_summary(row)
    return row[:listed].to_s if row[:unlisted].zero?

    "#{row[:listed]} (+#{row[:unlisted]} unlisted)"
  end
end
