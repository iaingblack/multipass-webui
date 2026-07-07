# frozen_string_literal: true

# Spike controller: minimal pages to prove the ActionCable + PTY path
# works end-to-end before building the real UI.
class SpikeController < ApplicationController
  # No auth on the spike — it's local-only, behind a real auth layer later.
  skip_before_action :verify_authenticity_token, only: [ :create_session ]

  def index
    @vms =
      begin
        Multipass::Client.new.list_vms.select { |v| v.state == "Running" }
      rescue Multipass::Client::CommandError
        []
      end
  end

  # POST /spike/terminals?vm_name=foo
  # Opens a PTY session and renders the terminal page.
  def create_session
    vm_name = params.require(:vm_name)

    # Generate a session ID the same way Go does: crypto-random hex
    session_id = SecureRandom.hex(16)
    Terminals::Session.open(vm_name:, session_id:)

    redirect_to spike_terminal_path(vm_name:, session_id:)
  rescue Multipass::NameValidator::ValidationError
    render plain: "invalid VM name", status: :bad_request
  end

  # GET /spike/terminal?vm_name=foo&session_id=bar
  def terminal
    @vm_name = params[:vm_name]
    @session_id = params[:session_id]
    render :terminal, layout: "terminal_fullscreen"
  end

  # DELETE /spike/terminals/:session_id
  def destroy_session
    Terminals::Session.kill(params[:id])
    redirect_to spike_path, notice: "Session killed"
  end
end
