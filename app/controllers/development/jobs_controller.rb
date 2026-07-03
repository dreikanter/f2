class Development::JobsController < ApplicationController
  def index
    authorize [:development, :job], :index?
    @jobs = JobRun::RUNNABLE_JOBS
  end
end
