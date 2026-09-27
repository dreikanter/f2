module Features
  def self.ai?
    Rails.configuration.x.features.ai
  end

  def self.external_search?
    Rails.configuration.x.features.external_search
  end
end
