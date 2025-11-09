class FreefeedUserComponent < ViewComponent::Base
  def initialize(username:)
    @username = username
  end

  private

  def avatar_classes
    class_names(
      "w-12 h-12",
      "bg-slate-200",
      "rounded-md"
    )
  end
end
