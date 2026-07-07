# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShellSessionsController, type: :request do
  # Stub auth — request specs need a valid session
  before do
    session = Session.create!(token_hash: Session.hash_token("test"), expires_at: 1.hour.from_now)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
  end

  describe "GET /vms/:name/shell_sessions" do
    it "rejects invalid VM names" do
      get "/vms/--all/shell_sessions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to match(/invalid VM name/)
    end
  end

  describe "POST /vms/:name/shell_sessions" do
    it "rejects when VM is not found" do
      allow_any_instance_of(Multipass::Client).to receive(:get_vm_info)
        .and_raise(Multipass::Client::CommandError.new(%w[info nope], FakeStatusHelper.failure, "", "not found"))
      post "/vms/missing-vm/shell_sessions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end

    it "rejects when VM is not Running" do
      stopped = Multipass::Types::VmInfo.new(name: "stopped-vm", state: "Stopped")
      allow_any_instance_of(Multipass::Client).to receive(:get_vm_info).and_return(stopped)
      post "/vms/stopped-vm/shell_sessions", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to match(/must be Running/)
    end
  end

  describe "DELETE /vms/:name/shell_sessions/:id" do
    it "kills the session if it exists" do
      session_id = "deadbeef"
      allow(Terminals::Session).to receive(:kill).with(session_id)
      delete "/vms/some-vm/shell_sessions/#{session_id}", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(Terminals::Session).to have_received(:kill).with(session_id)
    end
  end
end

# Tiny helper for stubbing failure status in command-error tests.
class FakeStatusHelper
  def self.failure
    Struct.new(:success?, :exitstatus).new(false, 1)
  end
end
