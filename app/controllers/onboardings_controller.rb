class OnboardingsController < ApplicationController
  skip_onboarding_redirect

  def show
    @onboarding = Current.user.onboarding
    redirect_to redirect_path_after_onboarding unless @onboarding
  end

  def create
    onboarding = Onboarding.find_or_initialize_by(user: Current.user)
    onboarding.current_step = :intro
    onboarding.save!
    session[:onboarding] = true
    redirect_to onboarding_path
  end

  def update
    onboarding = Current.user.onboarding
    return redirect_to redirect_path_after_onboarding unless onboarding

    if onboarding.last_step?
      complete_onboarding
    else
      onboarding.update!(current_step: onboarding.next_step)
      redirect_to onboarding_path
    end
  end

  def destroy
    clear_onboarding
    redirect_to redirect_path_after_onboarding
  end

  private

  def clear_onboarding
    Current.user.onboarding&.destroy
    session[:onboarding] = false
  end

  def complete_onboarding
    clear_onboarding
    redirect_to redirect_path_after_onboarding, notice: "Setup complete. Your feed is ready to go."
  end

  def redirect_path_after_onboarding
    status_path
  end
end
