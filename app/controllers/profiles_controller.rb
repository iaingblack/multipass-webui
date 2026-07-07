# frozen_string_literal: true

class ProfilesController < ApplicationController
  def index
    @profiles = Profile.all.order(:name)
  end

  def new
    @profile = Profile.new(release: Multipass::Constants::DEFAULT_UBUNTU_RELEASE)
  end

  def create
    @profile = Profile.new(profile_params.merge(id_slug: generate_id_slug))
    if @profile.save
      Event.emit_http!(category: "config", action: "create_profile",
                       resource: @profile.id_slug, result: "success", request: request)
      redirect_to profiles_path, notice: "Created #{@profile.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @profile = Profile.find(params[:id])
  end

  def update
    @profile = Profile.find(params[:id])
    if @profile.update(profile_params)
      Event.emit_http!(category: "config", action: "update_profile",
                       resource: @profile.id_slug, result: "success", request: request)
      redirect_to profiles_path, notice: "Updated #{@profile.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile = Profile.find(params[:id])
    return redirect_to profiles_path, alert: "Cannot delete built-in profile" if @profile.builtin?

    @profile.destroy
    Event.emit_http!(category: "config", action: "delete_profile",
                     resource: @profile.id_slug, result: "success", request: request)
    redirect_to profiles_path, notice: "Deleted #{@profile.name}."
  end

  private

  def profile_params
    params.require(:profile).permit(:name, :release, :cpus, :memory_mb, :disk_gb,
                                    :cloud_init, :network, :playbook, :group_name)
  end

  def generate_id_slug
    base = params[:profile][:name].to_s.downcase.gsub(/[^a-z0-9_-]/, "-").gsub(/-{2,}/, "-")
    base = "profile" if base.blank?
    base + "-" + SecureRandom.hex(2)
  end
end
