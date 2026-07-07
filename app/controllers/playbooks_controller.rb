# frozen_string_literal: true

# Ansible playbook CRUD. Playbooks are YAML files on disk under
# playbooks_dir. Used by the playbook runner (Phase 5).
class PlaybooksController < ApplicationController
  def index
    @playbooks = Multipass::Playbooks.list_playbooks(playbooks_dir)
    respond_to do |format|
      format.html
      format.json { render json: @playbooks }
    end
  end

  def new
    @playbook = Struct.new(:name, :content).new("", default_content)
  end

  def create
    name = params[:name]
    content = params[:content]
    Multipass::Playbooks.write_playbook(playbooks_dir, name, content)
    Event.emit_http!(category: "ansible", action: "create_playbook",
                     resource: name, result: "success", request: request)
    redirect_to playbooks_path, notice: "Created #{name}."
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    @playbook = Struct.new(:name, :content).new(name, content)
    render :new, status: :unprocessable_entity
  end

  def edit
    @playbook = Struct.new(:name, :content).new(
      params[:name],
      Multipass::Playbooks.read_playbook(playbooks_dir, params[:name])
    )
  rescue ArgumentError => e
    redirect_to playbooks_path, alert: e.message
  end

  def update
    name = params[:name]
    content = params[:content]
    Multipass::Playbooks.write_playbook(playbooks_dir, name, content)
    Event.emit_http!(category: "ansible", action: "update_playbook",
                     resource: name, result: "success", request: request)
    redirect_to playbooks_path, notice: "Saved #{name}."
  rescue ArgumentError => e
    redirect_to edit_playbook_path(name), alert: e.message
  end

  def destroy
    name = params[:name]
    Multipass::Playbooks.delete_playbook(playbooks_dir, name)
    Event.emit_http!(category: "ansible", action: "delete_playbook",
                     resource: name, result: "success", request: request)
    redirect_to playbooks_path, notice: "Deleted #{name}."
  rescue ArgumentError => e
    redirect_to playbooks_path, alert: e.message
  end

  def show
    content = Multipass::Playbooks.read_playbook(playbooks_dir, params[:name])
    render plain: content
  end

  private

  def playbooks_dir
    Setting.current.playbooks_dir.presence ||
      File.expand_path("~/.multipass-webui/playbooks")
  end

  def default_content
    <<~YAML
      ---
      - name: Example playbook
        hosts: all
        become: false
        tasks:
          - name: Ping hosts
            ansible.builtin.ping:
    YAML
  end
end
