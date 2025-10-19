Rails.application.routes.draw do
  # TBD: Use custom authentication + permission-based access control
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resource :session
  resources :email_confirmations, only: :show, param: :token
  resource :status, only: :show, controller: "statuses"
  resources :passwords, param: :token
  resources :invites, only: [:index, :create, :destroy]
  resource :registration, only: [:show, :create], path: "register"
  resources :posts, only: [:index, :show, :destroy]
  resources :feed_previews, only: [:create, :show, :update], path: "previews"
  resource :admin, only: :show

  resource :onboarding, only: [:show, :create, :destroy] do
    scope module: :onboarding do
      resource :intro, only: :show
      resource :access_token, only: [:show, :create]
      resource :validation, only: :create
      resource :feed, only: :show
      resource :outro, only: :show
    end
  end

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
    resource :purge, only: [:show, :create], controller: "feeds/purges"
  end

  namespace :admin do
    resources :users, only: [:index, :show] do
      resource :email_update, only: [:edit, :update]
      resource :password_reset, only: [:show, :create]
      resource :suspension, only: [:create, :destroy], controller: "user_suspensions"
      resource :available_invites, only: :update, controller: "available_invites"
    end

    resources :events, only: [:index, :show]
    resource :system_stats, only: :show
  end

  resource :settings, only: :show do
    resource :email_update, only: [:edit, :update], controller: "settings/email_updates"
    resource :password_update, only: [:edit, :update], controller: "settings/password_updates"

    resources :access_tokens, controller: "settings/access_tokens" do
      resource :validation, only: [:show, :create], controller: "settings/access_token_validations"
      resources :groups, only: :index, controller: "settings/access_token_groups"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "landing#index"
end
