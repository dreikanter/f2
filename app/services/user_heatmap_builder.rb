class UserHeatmapBuilder
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Generates and caches the heatmap SVG
  # @param expires_in [ActiveSupport::Duration] Cache expiration time
  # @param force [Boolean] Force cache refresh
  # @return [String] SVG markup
  def build_cached(expires_in: 24.hours, force: false)
    Rails.cache.fetch(cache_key, expires_in: expires_in, force: force) { build }
  end

  # Generates the heatmap SVG without caching
  # @return [String] SVG markup
  def build
    data = user.posts_heatmap_data

    HeatmapBuilder.build_calendar(
      values: data,
      show_month_labels: true,
      show_day_labels: true
    )
  end

  private

  def cache_key
    "user:#{user.id}:heatmap_svg:#{Date.current}"
  end
end
