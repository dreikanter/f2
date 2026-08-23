module FaviconHelper
  # Non-production deployments serve a green tile so a staging or development
  # tab is obvious among production ones. Takes the environment as an argument
  # rather than reading Rails.env inline, so tests can exercise both branches
  # without stubbing.
  def favicon_path(extension, env = Rails.env)
    basename = env.to_s == "production" ? "icon" : "icon-green"
    "/#{basename}.#{extension}"
  end
end
