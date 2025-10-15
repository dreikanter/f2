module UserOnboarding
  extend ActiveSupport::Concern

  included do
    before_action :redirect_to_onboarding
  end

  class_methods do
    def skip_onboarding_redirect(**options)
      skip_before_action :redirect_to_onboarding, **options
    end
  end

  private

  def redirect_to_onboarding
    return unless session[:onboarding]
    return if controller_name == "onboardings"

    redirect_to onboarding_path
  end
end
