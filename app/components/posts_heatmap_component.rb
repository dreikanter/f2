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
end
