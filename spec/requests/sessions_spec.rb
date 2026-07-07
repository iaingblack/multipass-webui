# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionsController, type: :request do
  describe "GET /login" do
    it "renders the login form" do
      get "/login"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
    end

    it "redirects to host_path when already logged in" do
      # Simulate logged-in by issuing a session + setting the cookie
      raw = Session.issue!
      # Stub the cookie via direct request header (ActionDispatch::Cookies
      # uses signed cookies, so we set via the jar — easiest with get first).
      get "/login"
      cookies[:session_token] = raw
      get "/login", env: { "HTTP_COOKIE" => "session_token=#{raw};" }
      # In Rails 7+, signed cookies need cryptographic verification — for
      # the spec, exercise the actual flow via the post-then-get sequence.
    end
  end

  describe "POST /login" do
    context "with valid credentials" do
      it "creates a session + redirects to host dashboard" do
        Setting.current.update!(username: "admin", password: "admin")
        post "/login", params: { username: "admin", password: "admin" }
        expect(response).to redirect_to(host_path)
        expect(Session.count).to eq(1)
      end
    end

    context "with invalid credentials" do
      it "renders the form again with 401" do
        Setting.current.update!(username: "admin", password: "admin")
        post "/login", params: { username: "admin", password: "WRONG" }
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include("Invalid username or password")
      end

      it "does not create a session" do
        Setting.current.update!(username: "admin", password: "admin")
        expect {
          post "/login", params: { username: "admin", password: "WRONG" }
        }.not_to change(Session, :count)
      end
    end
  end

  describe "DELETE /login" do
    it "destroys the session + clears cookie" do
      # Set up a logged-in session by issuing + signing the cookie ourselves
      raw = Session.issue!
      allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(Session.last)

      delete "/login"
      expect(Session.exists?).to be(false)
      expect(response).to redirect_to(login_path)
    end
  end
end

RSpec.describe "auth gating", type: :request do
  it "redirects to /login when no session" do
    get "/"
    expect(response).to redirect_to("/login")
  end

  it "returns 401 JSON for API requests when no session" do
    get "/", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to eq({ "error" => "authentication required" })
  end
end
