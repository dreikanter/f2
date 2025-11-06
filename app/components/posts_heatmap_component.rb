class PostsHeatmapComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  def call
    data = user.posts_heatmap_data
    return if data.empty?

    tag.div(heatmap_svg.html_safe, class: "heatmap-container flex justify-center")
  end

  private

  attr_reader :user

  def heatmap_svg
    UserHeatmapBuilder.new(user).build_cached
  end
end
