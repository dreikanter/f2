Rails.application.routes.draw do
  resource :dashboard, only: :show
  resource :session
  resources :passwords, param: :token
  resources :feeds

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
