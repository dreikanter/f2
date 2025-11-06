class PostsHeatmapComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  def call
    return unless @user.total_imported_posts_count.positive?

    tag.div(class: "space-y-2") do
      tag.h3("Activity", class: "ff-h3") +
      tag.div(heatmap_svg.html_safe, class: "heatmap-container")
    end
  end

  private

  attr_reader :user

  def heatmap_svg
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      generate_heatmap_svg
    end
  end

  def generate_heatmap_svg
    data = user.posts_heatmap_data
    end_date = Date.current
    start_date = end_date - 365

    builder = HeatmapBuilder.new(
      data: data,
      start_date: start_date,
      end_date: end_date,
      month_labels: true,
      day_labels: true
    )

    builder.to_svg
  end

  def cache_key
    # Cache key includes user ID and the date to ensure daily updates
    # This will be explicitly invalidated when new posts are imported
    "user:#{user.id}:heatmap_svg:#{Date.current}"
  end
end
