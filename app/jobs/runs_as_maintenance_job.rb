# What the dev area needs from a job listed in JobRun::RUNNABLE_JOBS. Jobs the
# app schedules for itself carry none of this; it exists for the ones an
# operator browses and launches by hand.
module RunsAsMaintenanceJob
  extend ActiveSupport::Concern

  included do
    # Maintenance work is unrelated to feed traffic, so it runs in its own pool
    # and stays available while the other queues are paused.
    queue_as :service
  end

  class_methods do
    # How the dev area names this job: the class name read as prose, so listings
    # and breadcrumbs don't spell out Ruby constants.
    def display_name = name.delete_suffix("Job").titleize
  end
end
