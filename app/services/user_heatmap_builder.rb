class UserHeatmapBuilder
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Generates and caches the heatmap SVG
  # @param expires_in [ActiveSupport::Duration] Cache expiration time
  # @return [String] SVG markup
  def build_cached(expires_in: 24.hours)
    Rails.cache.fetch(cache_key, expires_in: expires_in) do
      build
    end
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

  # Invalidates the cached heatmap for this user
  def invalidate_cache
    Rails.cache.delete(cache_key)
  end

  # Warms up the cache by generating and storing the heatmap
  # Used in background jobs after data changes
  # @param expires_in [ActiveSupport::Duration] Cache expiration time
  def warm_cache(expires_in: 24.hours)
    Rails.cache.write(cache_key, build, expires_in: expires_in)
  end

  private

  def cache_key
    "user:#{user.id}:heatmap_svg:#{Date.current}"
  end
end
