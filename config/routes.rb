Rails.application.routes.draw do
  # TBD: Use custom authentication + permission-based access control
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :access_tokens, only: [:index, :new, :create, :destroy] do
    resource :validation, only: [:show, :create], controller: 'access_token_validations'
  end

  resource :profile, only: :show
  resource :email_update, only: :update
  resource :password_update, only: :update
  resources :email_confirmations, only: :show, param: :token
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token
  resources :feeds
  resources :events, only: [:index, :show]

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
