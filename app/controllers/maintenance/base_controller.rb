module Maintenance
  # Token-authenticated, plain-text interface for running maintenance jobs from
  # the command line or an agent — curl-friendly, minimal output. Parallel to
  # the session-based dev-area UI (Development::JobRunsController), not a
  # replacement.
  #
  # Inert unless MAINTENANCE_JOB_TOKEN is set in the environment, so it exposes
  # nothing wherever the secret isn't configured. Inherits ActionController::Base
  # directly to skip the session auth and modern-browser gate that would reject a
  # bare curl request.
  class BaseController < ActionController::Base
    skip_forgery_protection
    before_action :authenticate_token!

    rescue_from ActiveRecord::RecordNotFound do
      render_text("not found", status: :not_found)
    end

    private

    def authenticate_token!
      token = ENV["MAINTENANCE_JOB_TOKEN"].to_s
      return render_text("maintenance interface is disabled (no MAINTENANCE_JOB_TOKEN)", status: :not_found) if token.blank?

      provided = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
      return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, token)

      render_text("unauthorized", status: :unauthorized)
    end

    def render_text(body, status: :ok)
      render plain: "#{body.to_s.chomp}\n", status: status
    end

    def find_job_class
      JobRun.runnable_job(params[:job_id]) || raise(ActiveRecord::RecordNotFound)
    end
  end
end
