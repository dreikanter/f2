class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def create
    restart_onboarding
    redirect_to onboarding_intro_path
  end

  def destroy
    Current.user.onboarding&.destroy
    complete_onboarding
  end

  private

  def restart_onboarding
    onboarding = Onboarding.find_or_create_by(user: Current.user)
    onboarding.update!(access_token: nil, feed: nil)
    session[:onboarding] = true
  end

  def complete_onboarding
    session[:onboarding] = false
    redirect_to status_path
  end
end
