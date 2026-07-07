# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
    @setting = Setting.current
    @vm_defaults = VmDefault.current
  end

  def update
    @setting = Setting.current
    if params[:setting].present?
      setting_params = params.require(:setting).permit(:username, :password, :cloud_init_dir,
                                                       :playbooks_dir, :trust_proxy)
      # Only update password if provided (don't blank it)
      setting_params.delete(:password) if setting_params[:password].blank?
      @setting.update!(setting_params)
    end

    if params[:vm_defaults].present?
      VmDefault.current.update!(params.require(:vm_defaults).permit(:cpus, :memory_mb, :disk_gb,
                                                                    :ssh_public_key, :ssh_private_key))
    end

    Event.emit_http!(category: "config", action: "update_settings", resource: "self",
                     result: "success", request: request)
    redirect_to settings_path, notice: "Settings saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_path, alert: e.message
  end
end
