# Raw-HTTP experiment: which response_format mode makes Kimi return
# parseable JSON, and how often output degrades to markdown-fenced JSON.
# Runs each mode (none / json_object / json_schema) several times.
class KimiStructuredOutputJob < KimiExperimentJob
  private

  def run_experiment
    attempts = KimiExperiment.structured_output_attempts

    attempts.each do |attempt|
      record_event(type: "job.kimi_experiment.attempt",
                   message: "#{attempt[:mode]} ##{attempt[:attempt]}: #{attempt[:outcome]} (HTTP #{attempt[:status]})",
                   level: attempt[:outcome] == "clean_json" ? :info : :warning, **attempt)
    end

    tally = attempts.group_by { |a| a[:mode] }.map do |mode, group|
      "#{mode}: #{group.count { |a| a[:outcome] == 'clean_json' }}/#{group.size} clean"
    end
    record_event(type: "job.kimi_experiment.completed",
                 message: "structured output — #{tally.join(', ')}",
                 tally: attempts.map { |a| a.slice(:mode, :attempt, :outcome, :status) })
  end
end
