Rails.application.routes.draw do
  # Spike routes — temporary, used to prove ActionCable + PTY works.
  # Will be removed once the real Vms::ConsoleTab is wired up.
  get "spike", to: "spike#index"
  post "spike/terminals", to: "spike#create_session"
  delete "spike/terminals/:id", to: "spike#destroy_session"
  get "spike/terminal", to: "spike#terminal", as: :spike_terminal

  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check
  root "spike#index"
end
