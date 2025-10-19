class Onboarding::OutroController < ApplicationController
  skip_onboarding_redirect

  def show
    @onboarding = Current.user.onboarding
    redirect_to status_path unless @onboarding
  end
end
