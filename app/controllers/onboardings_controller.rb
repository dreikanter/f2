class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def create
    restart_onboarding
    redirect_to onboarding_intro_path
  end

  def destroy
    skip_onboarding
    redirect_to status_path
  end

  private

  def restart_onboarding
    onboarding = Onboarding.find_or_create_by(user: Current.user)
    onboarding.update!(access_token: nil, feed: nil)
    session[:onboarding] = true
  end

  def skip_onboarding
    Current.user.onboarding&.destroy
    session[:onboarding] = false
  end
end
