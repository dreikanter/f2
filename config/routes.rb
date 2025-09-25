Rails.application.routes.draw do
  # TBD: Use custom authentication + permission-based access control
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :access_tokens do
    resource :validation, only: [:show, :create], controller: "access_token_validations"
    resources :groups, only: :index, controller: "access_token_groups"
  end

  resource :settings, only: :show
  resource :email_update, only: :update
  resource :password_update, only: :update
  resources :email_confirmations, only: :show, param: :token
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
  end

  resources :feed_previews, only: [:create, :show, :update], path: "previews"

  namespace :admin do
    resources :feed_profiles
  end

  resources :events, only: [:index, :show]

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
