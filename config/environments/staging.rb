require_relative "production"

Rails.application.configure do
  # Annotate rendered views and ViewComponents with source-file comments to ease
  # debugging on staging. This override applies only here, so production (the
  # parent config required above) keeps annotations off.
  config.action_view.annotate_rendered_view_with_filenames = true
end
