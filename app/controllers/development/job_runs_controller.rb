class Development::JobRunsController < ApplicationController
  def index
    authorize [:development, :job_run], :index?
    @job_class = find_job_class
    @runs = JobRun.where(job_class: @job_class.name).order(created_at: :desc)
  end

  def create
    authorize [:development, :job_run], :create?
    @job_class = find_job_class
    job_run = JobRun.create!(job_class: @job_class.name)
    JobRunnerJob.perform_later(job_run)
    redirect_to development_job_job_runs_path(@job_class.name), success: "#{@job_class.name} enqueued."
  end

  private

  def find_job_class
    JobRun.runnable_job(params[:job_id]) || raise(ActiveRecord::RecordNotFound)
  end
end
