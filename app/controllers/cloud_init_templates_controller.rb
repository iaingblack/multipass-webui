# frozen_string_literal: true

# Cloud-Init template CRUD. Templates are YAML files on disk under
# cloud_init_dir. Built-in templates (from the Go embed cloud-init/*.yml)
# are exposed read-only via app/views/cloud_init_templates/builtin/.
class CloudInitTemplatesController < ApplicationController
  # GET /cloud_init_templates
  def index
    @templates = (builtin_templates + user_templates).sort_by(&:label)
    respond_to do |format|
      format.html
      format.json { render json: @templates.map { |t| { label: t.label, path: t.path, built_in: t.built_in } } }
    end
  end

  # GET /cloud_init_templates/new
  def new
    @template = Struct.new(:name, :content).new("", default_content)
  end

  # POST /cloud_init_templates
  def create
    name = params[:name]
    content = params[:content]
    Multipass::Cloudinit.validate_cloud_init_yaml!(content)
    multipass.write_cloud_init_template(cloud_init_dir, name, content)
    Event.emit_http!(category: "config", action: "create_cloud_init_template",
                     resource: name, result: "success", request: request)
    redirect_to cloud_init_templates_path, notice: "Created #{name}."
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    @template = Struct.new(:name, :content).new(name, content)
    render :new, status: :unprocessable_entity
  end

  # GET /cloud_init_templates/:name/edit
  def edit
    @template = Struct.new(:name, :content).new(
      params[:name],
      read_template_content(params[:name])
    )
  end

  # PATCH /cloud_init_templates/:name
  def update
    name = params[:name]
    content = params[:content]
    Multipass::Cloudinit.validate_cloud_init_yaml!(content)
    multipass.write_cloud_init_template(cloud_init_dir, name, content)
    Event.emit_http!(category: "config", action: "update_cloud_init_template",
                     resource: name, result: "success", request: request)
    redirect_to cloud_init_templates_path, notice: "Saved #{name}."
  rescue ArgumentError => e
    redirect_to edit_cloud_init_template_path(name), alert: e.message
  end

  # DELETE /cloud_init_templates/:name
  def destroy
    name = params[:name]
    multipass.delete_cloud_init_template(cloud_init_dir, name)
    Event.emit_http!(category: "config", action: "delete_cloud_init_template",
                     resource: name, result: "success", request: request)
    redirect_to cloud_init_templates_path, notice: "Deleted #{name}."
  rescue ArgumentError => e
    redirect_to cloud_init_templates_path, alert: e.message
  end

  # GET /cloud_init_templates/:name/content
  def show
    content = read_template_content(params[:name])
    render plain: content
  end

  private

  # Built-in templates come from app/views/cloud_init_templates/builtin/*.yml.
  def builtin_templates
    dir = Rails.root.join("app/views/cloud_init_templates/builtin")
    return [] unless Dir.exist?(dir)
    Dir.children(dir).sort.select { |f| f.end_with?(".yml", ".yaml") }.map do |f|
      Multipass::Types::TemplateOption.new(
        label: "builtin:#{f}",
        path: builtin_path(f),
        built_in: true
      )
    end
  end

  def builtin_path(name)
    "builtin:#{name}"
  end

  def user_templates
    return [] unless Dir.exist?(cloud_init_dir)
    multipass.scan_cloud_init_templates([ cloud_init_dir ])
  end

  def read_template_content(name)
    if name.start_with?("builtin:")
      actual = name.sub("builtin:", "")
      File.read(Rails.root.join("app/views/cloud_init_templates/builtin/#{actual}"))
    else
      multipass.read_cloud_init_template(cloud_init_dir, name)
    end
  end

  def cloud_init_dir
    Setting.current.cloud_init_dir.presence ||
      File.expand_path("~/.multipass-webui/cloud-init")
  end

  def default_content
    "#cloud-config\n# Edit me\npackage_update: true\n"
  end
end
