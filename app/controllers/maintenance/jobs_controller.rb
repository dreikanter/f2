module Maintenance
  class JobsController < BaseController
    def index
      names = JobRun::RUNNABLE_JOBS.map(&:name)
      body = [
        "Runnable maintenance jobs:",
        *names.map { |name| "  #{name}" },
        "",
        "Run one:",
        "  curl -sX POST -H 'Authorization: Bearer $MAINTENANCE_JOB_TOKEN' \\",
        "    #{request.base_url}/maintenance/jobs/<JobClassName>/runs"
      ].join("\n")

      render_text(body)
    end
  end
end
