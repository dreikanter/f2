Rails.application.routes.draw do
  resource :profile, only: [:show]
  resources :email_updates, only: [:update]
  resources :password_updates, only: [:update]
  resources :email_confirmations, only: [:show], param: :token
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token
  resources :feeds

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
