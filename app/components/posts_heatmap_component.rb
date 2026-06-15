class PostsHeatmapComponent < ViewComponent::Base
  HEATMAP_DAYS = 365

  def initialize(user: nil, feed: nil)
    @user = user
    @feed = feed
    @end_date = Date.current
    @start_date = @end_date - HEATMAP_DAYS
  end

  def render?
    metrics_by_date.any?
  end

  def call
    render(CardComponent.new) do
      tag.div(class: "overflow-x-auto", data: { controller: "heatmap" }) do
        tag.div(class: "w-max mx-auto") do
          raw(heatmap_svg)
        end
      end
    end
  end

  private

  def heatmap_svg
    HeatmapBuilder.build_calendar(
      values: heatmap_values,
      tooltip: ->(date:, score:, value: nil) { value.to_i.to_s },
      tooltip_attribute: "data-tippy-content",
      border_lightness_factor: 1
    )
  end

  def heatmap_values
    # Include boundary dates so the calendar always spans the full year range,
    # regardless of how sparse the actual data is.
    { @start_date => 0, @end_date => 0 }.merge(metrics_by_date)
  end

  def metrics_by_date
    @metrics_by_date ||= base_scope
      .for_date_range(@start_date, @end_date)
      .group(:date)
      .sum(:published_posts_count)
      .transform_values(&:to_i)
  end

  def base_scope
    @feed ? @feed.feed_metrics : FeedMetric.for_user(@user)
  end
end
