class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def show
    @onboarding = Current.user.onboarding
  end

  def destroy
    Current.user.onboarding&.destroy
    redirect_to status_path
  end
end
