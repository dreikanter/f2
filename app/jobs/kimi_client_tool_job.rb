# RubyLLM-path experiment: does Kimi drive a client-side function tool
# (fixed-URL page fetch) through RubyLLM's tool loop and produce grounded
# output? Tests the bring-our-own-retrieval alternative to Moonshot's
# builtin search.
class KimiClientToolJob < KimiExperimentJob
  private

  def run_experiment
    result = KimiExperiment.client_tool_attempt

    record_event(type: "job.kimi_experiment.completed",
                 message: "client tool: #{result[:invocations]} invocation(s), " \
                          "#{result[:error] ? "error: #{result[:error]}" : "grounded=#{result[:grounded]}"}",
                 level: result[:error] || result[:invocations].zero? ? :warning : :info, **result)
  end
end
