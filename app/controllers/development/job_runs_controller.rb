class Development::JobRunsController < ApplicationController
  def index
    authorize [:development, :job_run], :index?
    @job_class = find_job_class
    @runs = JobRun.where(job_class: @job_class.name).order(created_at: :desc)
  end

  def show
    authorize [:development, :job_run], :show?
    @job_class = find_job_class
    @run = JobRun.where(job_class: @job_class.name).find(params[:id])
    @events = @run.events.order(created_at: :asc)
  end

  def create
    authorize [:development, :job_run], :create?
    @job_class = find_job_class

    # Insert the run before enqueuing so the worker can't pick the job up before
    # its JobRun exists; job_id is assigned at instantiation, ahead of enqueue.
    job = @job_class.new
    JobRun.create!(job_class: @job_class.name, job_id: job.job_id)
    job.enqueue

    redirect_to development_job_job_runs_path(@job_class.name), success: "#{@job_class.name} enqueued."
  end

  private

  def find_job_class
    JobRun.runnable_job(params[:job_id]) || raise(ActiveRecord::RecordNotFound)
  end
end
