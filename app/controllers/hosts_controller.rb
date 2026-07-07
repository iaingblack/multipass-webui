# frozen_string_literal: true

# Host dashboard + tree-sidebar partial. The tree is loaded inside a
# turbo_frame_tag so it can be polled independently of the main panel
# (mirrors the 3-second VM refresh in the Go app).
class HostsController < ApplicationController
  # GET / — host dashboard with summary cards + bulk actions.
  def show
    @vms = fetch_vms
    @launches = [] # TODO: launch tracker (Phase 2)
    @host_resources = fetch_host_resources
  end

  # GET /tree — sidebar partial only, rendered inside the turbo frame.
  # Hit on initial load and every 3s by the polling Stimulus controller.
  def tree
    @vms = fetch_vms
    render partial: "hosts/tree", formats: :html
  end

  private

  def fetch_vms
    multipass.list_vms
  rescue Multipass::Client::CommandError => e
    Rails.logger.warn("host VM list failed: #{e.message}")
    []
  end

  def fetch_host_resources
    res, errs = Multipass::HostResources.get
    Rails.logger.warn("host resources partial failure: #{errs.inspect}") if errs.any?
    res
  end
end
