require_relative "production"

Rails.application.configure do
  # Annotate rendered views and ViewComponents with source-file comments
  config.action_view.annotate_rendered_view_with_filenames = true
end
