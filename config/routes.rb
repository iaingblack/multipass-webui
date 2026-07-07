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

  # Spike routes — temporary, used to prove ActionCable + PTY works.
  # Will be removed once the real Vms::ConsoleTab is wired up.
  get "spike", to: "spike#index"
  post "spike/terminals", to: "spike#create_session"
  delete "spike/terminals/:id", to: "spike#destroy_session"
  get "spike/terminal", to: "spike#terminal", as: :spike_terminal

  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check
end
