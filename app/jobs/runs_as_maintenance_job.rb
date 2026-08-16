# What the dev area needs from a job listed in JobRun::RUNNABLE_JOBS. Jobs the
# app schedules for itself carry none of this — it exists for the ones an
# operator browses and launches by hand.
module RunsAsMaintenanceJob
  extend ActiveSupport::Concern

  class_methods do
    # How the dev area names this job: the class name read as prose, so listings
    # and breadcrumbs don't spell out Ruby constants.
    def display_name = name.delete_suffix("Job").titleize

    private

    # The view's tag builders, reachable from a job class. Composing a
    # description through them is what keeps it safe: the parts a job
    # interpolates are escaped, and only the tags it builds here are markup.
    def helpers = ApplicationController.helpers
  end
end
