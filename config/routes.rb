Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  root "home#index"

  get "kindergarten/login", to: "kindergarten_sessions#new", as: :kindergarten_login
  post "kindergarten/login", to: "kindergarten_sessions#create"
  delete "kindergarten/logout", to: "kindergarten_sessions#destroy", as: :kindergarten_logout

  get "center/login", to: "center_sessions#new", as: :center_login
  post "center/login", to: "center_sessions#create"
  delete "center/logout", to: "center_sessions#destroy", as: :center_logout

  resources :dishes, only: [ :new, :create ]
  resources :feedback_targets, only: [ :new, :create ]
  resources :reactions, only: [ :new ]
end
