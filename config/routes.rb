Rails.application.routes.draw do
  # TBD: Use custom authentication + permission-based access control
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resource :settings, only: :show do
    resource :email_update, only: [:edit, :update], controller: "settings/email_updates"
    resource :password_update, only: [:edit, :update], controller: "settings/password_updates"

    resources :access_tokens, controller: "settings/access_tokens" do
      resource :validation, only: [:show, :create], controller: "settings/access_token_validations"
      resources :groups, only: :index, controller: "settings/access_token_groups"
    end
  end

  resources :email_confirmations, only: :show, param: :token
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
  end

  resources :posts, only: [:index, :show, :destroy]
  resources :feed_previews, only: [:create, :show, :update], path: "previews"
  resource :admin, only: :show

  namespace :admin do
    resources :feed_profiles
    resources :events, only: [:index, :show]
    resources :purges, only: [:new, :create]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
