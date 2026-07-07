# frozen_string_literal: true

# Manages PTY shell sessions for a VM. Sessions live in the Puma process
# memory (Terminals::Session::SESSIONS) and outlive individual WebSocket
# disconnects — refresh the page and the shell is still running, with
# up to 64KB of scrollback replayed on reconnect.
#
# Routes:
#   GET    /vms/:name/shell_sessions         — list active sessions
#   POST   /vms/:name/shell_sessions         — open a new session
#   DELETE /vms/:name/shell_sessions/:id     — kill a session
class ShellSessionsController < ApplicationController
  # JSON requests from external scripts skip CSRF — the action still requires
  # a valid session cookie or Bearer token (require_login still runs).
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_vm_name
  before_action :require_running_vm, only: %i[create]

  # GET /vms/:name/shell_sessions — JSON list of active sessions for this VM.
  def index
    sessions = Terminals::Session.for_vm(@vm_name).map do |id, sess|
      { id:, vm_name: sess.vm_name, created_at: sess.created_at }
    end
    render json: sessions
  end

  # POST /vms/:name/shell_sessions — open a new PTY session.
  # Returns the session_id; the browser then opens a WebSocket to
  # /cable and subscribes to TerminalChannel with that id.
  def create
    session_id = SecureRandom.hex(16)
    Terminals::Session.open(vm_name: @vm_name, session_id:)
    Event.emit_http!(category: "vm", action: "open_shell",
                     resource: @vm_name, result: "success",
                     detail: "session #{session_id}", request: request)
    render json: { id: session_id, vm_name: @vm_name }
  rescue Multipass::NameValidator::ValidationError => e
    render json: { error: e.message }, status: :bad_request
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # DELETE /vms/:name/shell_sessions/:id — kill a session.
  def destroy
    Terminals::Session.kill(params[:id])
    Event.emit_http!(category: "vm", action: "close_shell",
                     resource: @vm_name, result: "success",
                     detail: "session #{params[:id]}", request: request)
    render json: { message: "killed" }
  end

  private

  def set_vm_name
    # Route param is :name (nested under resources :vms, param: :name).
    @vm_name = params[:vm_name] || params[:name]
    Multipass::NameValidator.validate_vm_name!(@vm_name)
  rescue Multipass::NameValidator::ValidationError => e
    render json: { error: e.message }, status: :bad_request
  end

  def require_running_vm
    vm = multipass.get_vm_info(@vm_name)
    return if vm.state == "Running"

    render json: { error: "VM must be Running to open a shell (current: #{vm.state})" },
           status: :conflict
  rescue Multipass::Client::CommandError => e
    render json: { error: e.message }, status: :not_found
  end
end
