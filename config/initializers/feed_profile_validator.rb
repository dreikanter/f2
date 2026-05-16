Rails.application.config.after_initialize do
  FeedProfile::Validator.validate!
end
