Rails.application.routes.draw do
  # Auth
  get  "login",  to: "sessions#new",    as: :login
  post "login",  to: "sessions#create"
  delete "login", to: "sessions#destroy"

  # Host dashboard (root)
  root "hosts#show", as: :host
  get "tree", to: "hosts#tree"

  # VM resources
  resources :vms, only: %i[index show create destroy], param: :name do
    member do
      post :start
      post :stop
      post :suspend
      post :recover
      post :clone
      get  :resource_config
      patch :resource_config, to: "vms#update_resource_config"

      # Terminal sessions (Phase 3 full)
      resources :shell_sessions, only: %i[index create destroy], param: :id
      get :console, to: "vms#console"

      # VNC (Phase 7 polish) — links out to websockify-hosted noVNC
      get :vnc, to: "vms#vnc"
    end
    collection do
      post :start_all
      post :stop_all
      post :purge
    end
  end

  # Cloud-Init templates + Ansible playbooks
  resources :cloud_init_templates, param: :name
  resources :playbooks, param: :name

  # Configuration sections
  resources :profiles, param: :id
  resources :schedules, param: :id
  resources :api_tokens, param: :id
  resources :webhooks, param: :id do
    member { post :test }
  end
  resources :events, only: %i[index]
  resource :settings, only: %i[show update]


  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check
end
