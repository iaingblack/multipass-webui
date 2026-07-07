# frozen_string_literal: true

# VM management. Wraps the Multipass::Client for HTTP callers — every
# state-changing action emits an Event row for the audit log.
class VmsController < ApplicationController
  before_action :set_vm_name, only: %i[show destroy start stop suspend recover clone resource_config update_resource_config console vnc]

  # GET /vms — JSON API
  def index
    @vms = multipass.list_vms
    render json: @vms.map { |v| serialize_vm(v) }
  rescue Multipass::Client::CommandError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # GET /vms/:name — VM detail panel.
  def show
    @vm = multipass.get_vm_info(@vm_name)
    respond_to do |format|
      format.html
      format.json { render json: serialize_vm(@vm) }
    end
  rescue Multipass::Client::CommandError => e
    render json: { error: e.message }, status: :not_found
  end

  # POST /vms — VM launch. Runs synchronously for now; Phase 2 polish will
  # move this to a Vms::LaunchJob (matches Go's async launch tracker).
  def create
    name = multipass.launch_vm(
      name: params[:name].presence,
      release: params[:release].presence,
      cpus: params[:cpus].presence&.to_i,
      memory_mb: params[:memory_mb].presence&.to_i,
      disk_gb: params[:disk_gb].presence&.to_i,
      cloud_init_file: params[:cloud_init_file].presence,
      network_name: params[:network_name].presence
    )
    Event.emit_http!(category: "vm", action: "create", resource: name,
                     result: "success", detail: "launched", request: request)
    respond_to do |format|
      format.html { redirect_to vm_path(name), notice: "Launched #{name}." }
      format.json { render json: { name:, state: "launched" }, status: :accepted }
    end
  rescue Multipass::NameValidator::ValidationError => e
    render_error(e.message, :bad_request)
  rescue Multipass::Client::CommandError => e
    Event.emit_http!(category: "vm", action: "create", resource: params[:name],
                     result: "failed", detail: e.message, request: request)
    render_error(e.message, :internal_server_error)
  end

  def destroy
    purge = ActiveModel::Type::Boolean.new.cast(params[:purge])
    multipass.delete_vm(@vm_name, purge:)
    Event.emit_http!(category: "vm", action: "delete", resource: @vm_name,
                     result: "success", detail: purge ? "purged" : "deleted",
                     request: request)
    respond_to do |format|
      format.html { redirect_to host_path, notice: "Deleted #{@vm_name}." }
      format.json { render json: { message: "deleted" } }
    end
  rescue Multipass::Client::CommandError => e
    render_error(e.message, :internal_server_error)
  end

  def start = perform_lifecycle(:start_vm, "start")
  def stop  = perform_lifecycle(:stop_vm, "stop")
  def suspend = perform_lifecycle(:suspend_vm, "suspend")
  def recover = perform_lifecycle(:recover_vm, "recover")

  def clone
    dest = multipass.clone_vm(@vm_name, dest_name: params[:dest_name].presence)
    Event.emit_http!(category: "vm", action: "clone", resource: @vm_name,
                     result: "success", detail: "→ #{dest}", request: request)
    respond_to do |format|
      format.html { redirect_to vm_path(dest || @vm_name), notice: "Cloned." }
      format.json { render json: { name: dest } }
    end
  rescue Multipass::Client::CommandError => e
    render_error(e.message, :internal_server_error)
  end

  def resource_config
    @vm = multipass.get_vm_info(@vm_name)
    @config = multipass.get_vm_config(@vm_name)
    respond_to do |format|
      format.html
      format.json { render json: { cpus: @config.cpus, memory_mb: @config.memory_mb, disk_gb: @config.disk_gb } }
    end
  rescue Multipass::Client::CommandError => e
    render_error(e.message, :not_found)
  end

  def update_resource_config
    multipass.set_vm_cpus(@vm_name, params[:cpus].to_i)   if params[:cpus].present?
    multipass.set_vm_memory(@vm_name, params[:memory_mb].to_i) if params[:memory_mb].present?
    multipass.set_vm_disk(@vm_name, params[:disk_gb].to_i)     if params[:disk_gb].present?
    Event.emit_http!(category: "vm", action: "resize", resource: @vm_name,
                     result: "success", detail: "reconfigured", request: request)
    redirect_to vm_path(@vm_name), notice: "Config updated."
  rescue Multipass::Client::CommandError => e
    render_error(e.message, :internal_server_error)
  end

  def start_all
    multipass.start_all
    redirect_to host_path, notice: "Started all stopped VMs."
  rescue Multipass::Client::CommandError => e
    redirect_to host_path, alert: "Start-all: #{e.message}"
  end

  def stop_all
    multipass.stop_all
    redirect_to host_path, notice: "Stopped all running VMs."
  rescue Multipass::Client::CommandError => e
    redirect_to host_path, alert: "Stop-all: #{e.message}"
  end

  def purge
    multipass.purge_deleted
    redirect_to host_path, notice: "Purged deleted VMs."
  rescue Multipass::Client::CommandError => e
    redirect_to host_path, alert: "Purge: #{e.message}"
  end

  # GET /vms/:name/console — full-screen terminal page.
  # Opens its own session via the ShellSessionsController on first load.
  def console
    @vm = multipass.get_vm_info(@vm_name)
    # Find an existing session for this VM, or create one
    existing = Terminals::Session.for_vm(@vm_name).keys.first
    @session_id = existing || begin
      sid = SecureRandom.hex(16)
      Terminals::Session.open(vm_name: @vm_name, session_id: sid)
      sid
    end
  rescue Multipass::Client::CommandError => e
    redirect_to vm_path(@vm_name), alert: e.message
  end

  # GET /vms/:name/vnc — VNC info page. Links out to a websockify-hosted
  # noVNC client. websockify must run separately on the host:
  #
  #   websockify --web /usr/share/novnc/ 6080 <vm_ip>:<port>
  #
  # See deploy/vnc-websockify.service for a systemd unit template.
  def vnc
    @vm = multipass.get_vm_info(@vm_name)
    @vnc_port = (params[:port] || 5900).to_i
    @vm_ip = @vm.ipv4.first
    @websockify_port = (params[:ws_port] || 6080).to_i
    @websockify_url = "http://#{request.host}:#{@websockify_port}/vnc.html?host=#{request.host}&port=#{@websockify_port}&autoconnect=true"
  rescue Multipass::Client::CommandError => e
    redirect_to vm_path(@vm_name), alert: e.message
  end

  private

  def set_vm_name
    @vm_name = params[:name]
    Multipass::NameValidator.validate_vm_name!(@vm_name)
  rescue Multipass::NameValidator::ValidationError => e
    render_error(e.message, :bad_request)
  end

  def perform_lifecycle(method, action_name)
    multipass.send(method, @vm_name)
    Event.emit_http!(category: "vm", action: action_name, resource: @vm_name,
                     result: "success", detail: action_name, request: request)
    respond_to do |format|
      format.html { redirect_to vm_path(@vm_name), notice: "#{action_name.capitalize} issued." }
      format.json { render json: { message: action_name } }
    end
  rescue Multipass::Client::CommandError => e
    Event.emit_http!(category: "vm", action: action_name, resource: @vm_name,
                     result: "failed", detail: e.message, request: request)
    render_error(e.message, :internal_server_error)
  end

  def render_error(message, status)
    respond_to do |format|
      format.html { redirect_to host_path, alert: message }
      format.json { render json: { error: message }, status: }
      format.turbo_stream { render json: { error: message }, status: }
    end
  end

  def serialize_vm(vm)
    {
      name: vm.name,
      state: vm.state,
      ipv4: vm.ipv4,
      release: vm.release,
      cpus: vm.cpus,
      memory_usage: vm.memory_usage,
      memory_total: vm.memory_total,
      disk_usage: vm.disk_usage,
      disk_total: vm.disk_total,
      snapshots: vm.snapshots
    }
  end
end
