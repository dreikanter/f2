module HasOperationRuns
  extend ActiveSupport::Concern

  included do
    has_many :operation_runs, as: :subject, dependent: :destroy
  end

  # @param kind [Symbol, String] operation type
  # @return [OperationRun, nil] newest run of this type
  def latest_operation_run(kind)
    operation_runs.where(kind: kind).order(id: :desc).first
  end

  # @param kind [Symbol, String] operation type
  # @return [OperationRun, nil] active run of this type
  def active_operation_run(kind)
    operation_runs.where(kind: kind).active.first
  end
end
