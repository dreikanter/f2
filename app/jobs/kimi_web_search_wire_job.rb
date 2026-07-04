# Raw-HTTP experiment: does Moonshot's builtin $web_search engage on this
# endpoint/model? Runs the documented handshake twice — once letting the
# model decide, once forcing the tool via tool_choice — and records every
# request/response round verbatim.
class KimiWebSearchWireJob < KimiExperimentJob
  private

  def run_experiment
    verdicts = { "auto" => run_variant("auto", force_tool: false),
                 "forced" => run_variant("forced", force_tool: true) }

    record_event(type: "job.kimi_experiment.completed",
                 message: "builtin $web_search: " \
                          "#{verdicts.map { |name, v| "#{name}=#{v ? 'engaged' : 'ignored'}" }.join(' ')}",
                 level: verdicts.values.any? ? :info : :warning, **verdicts)
  end

  # Returns true when the model actually emitted a $web_search tool call.
  def run_variant(name, force_tool:)
    steps = KimiExperiment.web_search_steps(force_tool: force_tool)
    steps.each do |step|
      record_event(type: "job.kimi_experiment.step",
                   message: "#{name} round #{step[:round]}: status=#{step[:status]} " \
                            "finish=#{step[:finish_reason] || 'n/a'} grounded=#{step[:grounded] || false}",
                   level: step[:error] ? :warning : :info, variant: name, **step)
    end
    steps.any? { |step| step[:tool_calls].present? }
  end
end
