module LlmProvider
  PROVIDERS = { "openai" => Openai.new.freeze }.freeze

  class << self
    def all
      PROVIDERS.values
    end

    def names
      PROVIDERS.keys
    end

    def find(name)
      PROVIDERS.fetch(name.to_s)
    end
  end
end
