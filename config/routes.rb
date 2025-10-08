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
  get "status" => "dashboards#show", as: :dashboard
  resource :session
  resources :passwords, param: :token
  resources :invites, only: [:index, :create, :destroy]
  get "register" => "registrations#new", as: :new_registration
  post "register" => "registrations#create", as: :registrations

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
    resource :purge, only: [:show, :create], controller: "feeds/purges"
  end

  resources :posts, only: [:index, :show, :destroy]
  resources :feed_previews, only: [:create, :show, :update], path: "previews"
  resource :admin, only: :show

  namespace :admin do
    resources :users, only: [:index, :show] do
      resource :email_update, only: [:edit, :update]
      resource :password_reset, only: [:show, :create]
      resource :suspension, only: [:create, :destroy], controller: "user_suspensions"
      resource :available_invites, only: :update, controller: "available_invites"
    end
    resources :events, only: [:index, :show]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
end
