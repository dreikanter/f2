Rails.application.routes.draw do
  # TBD: Use custom authentication + permission-based access control
  mount MissionControl::Jobs::Engine, at: "/jobs"
  mount ActionCable.server => "/cable"

  resources :access_tokens, only: [:index, :new, :create, :destroy] do
    resources :token_validations, only: [:create] do
      member do
        get :status
      end
    end
  end
  resource :profile, only: :show
  resource :email_update, only: :update
  resource :password_update, only: :update
  resources :email_confirmations, only: :show, param: :token
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token
  resources :feeds

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
