Rails.application.routes.draw do
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
