module FaviconHelper
  def favicon_path(extension, env = Rails.env)
    basename = env.to_s == "production" ? "icon" : "icon-green"
    "/#{basename}.#{extension}"
  end
end
