Rails.application.routes.draw do
  if Rails.env.development? || Rails.env.test?
    namespace :development do
      resource :components, only: :show

      resources :sent_emails, only: [:index, :show], format: false do
        collection do
          delete :purge
        end
      end
    end
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

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
  resources :feed_entries, only: :show
  resources :feed_previews, only: [:create, :show, :update], path: "previews"
  resource :admin, only: :show

  resource :feed_details, only: [:create, :show], path: "feeds/details"

  resources :feeds do
    resource :status, only: :update, controller: "feed_statuses"
    resource :purge, only: :create, controller: "feeds/purges"
  end

  namespace :admin do
    resources :users, only: [:index, :show] do
      resource :email_update, only: [:edit, :update]
      resource :password_reset, only: :create
      resource :suspension, only: [:create, :destroy], controller: "user_suspensions"
      resource :available_invites, only: :update, controller: "available_invites"
      resource :email_reactivation, only: :create
    end

    resources :events, only: [:index, :show]
    resource :system_stats, only: :show
  end

  resource :settings, only: :show do
    resource :email_update, only: [:edit, :update], controller: "settings/email_updates"
    resource :password_update, only: [:edit, :update], controller: "settings/password_updates"
    resources :email_confirmations, only: :show, param: :token, controller: "settings/email_confirmations"

    resources :access_tokens, controller: "settings/access_tokens", except: [:edit, :update] do
      resource :validation, only: :show, controller: "settings/access_token_validations"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  resource :resend_webhooks, only: :create, path: "resend"

  root "landing#index"
end
