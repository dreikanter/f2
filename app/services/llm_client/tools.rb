class LlmClient
  module Tools
    # RubyLLM derives a tool's wire name from its class alone, so reading the
    # name needs no collaborators. `allocate` skips the initializer they feed.
    module WireName
      def tool_name
        @tool_name ||= allocate.name
      end
    end
  end
end
