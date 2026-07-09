module Maintenance
  # Runs a maintenance job synchronously and returns its recorded events as
  # plain text, so one curl call both triggers the job and shows the result.
  # Probe jobs are short and side-effect-free, which is what makes an inline run
  # the right fit here (unlike the dev UI, which enqueues).
  class RunsController < BaseController
    def create
      job_class = find_job_class
      job = job_class.new
      run = JobRun.create!(job_class: job_class.name, job_id: job.job_id)

      begin
        job.perform_now
      rescue StandardError => e
        # RecordsJobRun has already marked the run failed; report and still
        # render the run so the caller sees whatever events were recorded.
        Rails.error.report(e, context: { job_class: job_class.name })
      end

      render_text(JobRunReport.new(run.reload).to_text)
    end

    def show
      run = JobRun.where(job_class: find_job_class.name).find(params[:id])
      render_text(JobRunReport.new(run).to_text)
    end
  end
end
