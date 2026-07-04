# Base for the focused Kimi/Moonshot feasibility experiments (issue #913).
# Subclasses implement #run_experiment and record everything as JobRun events.
class KimiExperimentJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  def perform
    unless LlmCapabilityProbe::Provider.configured?("moonshot")
      record_event(type: "job.kimi_experiment.skipped",
                   message: "moonshot: no API key in environment", level: :warning)
      return
    end

    run_experiment
  end
end
