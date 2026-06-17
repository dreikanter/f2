Rails.application.routes.draw do
  resource :development, only: :show

  namespace :development do
    resource :components, only: :show
    resource :system_status, only: :show, controller: "system_status"
    resources :email_previews, only: [:index, :show]

    resources :sent_emails, only: [:index, :show], format: false do
      collection do
        delete :purge
      end
    end
  end

  constraints ->(req) {
    session = Session.find_by(id: req.cookie_jar.signed[:session_id])
    session&.user&.dev?
  } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  resource :session
  resource :status, only: :show, controller: "statuses"
  resources :passwords, param: :token
  resources :invites, only: [:index, :create, :destroy]
  resource :registration, only: [:show, :create], path: "register"

  namespace :registration do
    resource :confirmation_pending, only: :show
    resources :confirmations, only: [:new, :create]
    resources :email_confirmations, only: :show, param: :token
  end

  resources :posts, only: [:index, :show, :destroy]
  resources :events, only: [:index, :show]
  resources :feed_entries, only: :show
  resource :feed_preview, only: [:show, :create]
  resource :admin, only: :show

  resource :feed_identifications, only: [:create, :show, :destroy]

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
    resource :refresh, only: :create, controller: "feeds/refreshes"
    resource :purge, only: :create, controller: "feeds/purges"
  end

  namespace :admin do
    resources :users, only: [:index, :show] do
      resource :permissions, only: :update
      resource :email_update, only: [:edit, :update]
      resource :password_reset, only: :create
      resource :suspension, only: [:create, :destroy]
      resource :available_invites, only: :update
      resource :email_reactivation, only: :create
    end

    resources :events, only: [:index, :show]
  end

  resource :settings, only: :show

  namespace :settings do
    resource :email_update, only: [:edit, :update]
    resource :password_update, only: [:edit, :update]
    resources :email_confirmations, only: :show, param: :token
  end

  resources :access_tokens do
    scope module: :access_tokens do
      resource :validation, only: :show
      resources :groups, only: :index
    end
  end

  resources :ai_credentials do
    scope module: :ai_credentials do
      resource :validation, only: :show
      resource :default, only: :update
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  resource :resend_webhooks, only: :create, path: "resend"

  root "landing#index"
end
