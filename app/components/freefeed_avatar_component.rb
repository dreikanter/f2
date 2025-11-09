class FreefeedAvatarComponent < ViewComponent::Base
  def initialize(username:, size: "medium")
    @username = username
    @size = size
  end

  private

  def size_classes
    case @size
    when "small"
      "w-8 h-8"
    when "medium"
      "w-12 h-12"
    when "large"
      "w-16 h-16"
    else
      "w-12 h-12"
    end
  end

  def avatar_classes
    class_names(
      size_classes,
      "bg-slate-200",
      "rounded-md"
    )
  end
end
