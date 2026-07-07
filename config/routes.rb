Rails.application.routes.draw do
  # Auth
  get  "login",  to: "sessions#new",    as: :login
  post "login",  to: "sessions#create"
  delete "login", to: "sessions#destroy"

  # Host dashboard (root)
  root "hosts#show", as: :host
  get "tree", to: "hosts#tree"

  # Spike routes — temporary, used to prove ActionCable + PTY works.
  # Will be removed once the real Vms::ConsoleTab is wired up.
  get "spike", to: "spike#index"
  post "spike/terminals", to: "spike#create_session"
  delete "spike/terminals/:id", to: "spike#destroy_session"
  get "spike/terminal", to: "spike#terminal", as: :spike_terminal

  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check
end
