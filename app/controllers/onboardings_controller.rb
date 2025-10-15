class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def create
    Current.user.create_onboarding!
    session[:onboarding] = true
    redirect_to onboarding_path
  end

  def destroy
    Current.user.onboarding&.destroy
    session[:onboarding] = false
    redirect_to status_path
  end
end
