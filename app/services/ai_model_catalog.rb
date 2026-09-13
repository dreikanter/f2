class AiModelCatalog
  UNAVAILABLE_MESSAGE = "AI model discovery is temporarily unavailable. Your saved settings are still available.".freeze

  class Unavailable < StandardError; end

  def self.fetch(credential)
    raise Unavailable, UNAVAILABLE_MESSAGE
  end
end
