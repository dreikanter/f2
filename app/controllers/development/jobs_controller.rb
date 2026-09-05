class Development::JobsController < ApplicationController
  def index
    authorize [:development, :job], :index?
    @jobs = JobRun.runnable_jobs
  end
end
