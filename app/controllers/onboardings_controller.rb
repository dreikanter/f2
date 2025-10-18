class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def show
    @onboarding = Current.user.onboarding
    return complete_onboarding unless @onboarding

    @current_step = current_step
  end

  def destroy
    Current.user.onboarding&.destroy
    complete_onboarding
  end

  private

  def complete_onboarding
    session[:onboarding] = false
    redirect_to status_path
  end

  def current_step
    # TBD: Drop test parameter
    case params[:step]
    when "1" then :intro
    when "2" then :feed
    when "3" then :outro
    else
      if @onboarding.token_setup?
        :intro
      elsif @onboarding.feed_setup?
        :feed
      else
        :outro
      end
    end
  end
end
