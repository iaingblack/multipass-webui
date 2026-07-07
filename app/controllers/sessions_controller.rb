# frozen_string_literal: true

# Login + logout. Mirrors handlers_auth.go in the Go version:
#   POST /login   — bcrypt-compare, issue 24h session, set cookie
#   DELETE /login — destroy session, clear cookie
#
# Rate limiting (5 attempts/min per IP) is wired via rack-attack in
# config/initializers/rack_attack.rb — same threshold as Go's
# loginRateLimiter at internal/api/middleware.go:178-251.
class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  # GET /login — render the form.
  def new
    redirect_to root_path if logged_in?
  end

  # POST /login — validate credentials, issue session.
  def create
    setting = Setting.current

    if setting.authenticate(params[:password].to_s) &&
       setting.username == params[:username].to_s
      # Issue the session — raw token returned once, hash stored.
      raw_token = Session.issue!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      cookies.signed[:session_token] = {
        value: raw_token,
        expires: Session::TTL_HOURS.hours.from_now,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }
      redirect_to host_path, notice: "Signed in."
    else
      # Don't disclose which field was wrong.
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unauthorized
    end
  end

  # DELETE /login — clear session + cookie.
  def destroy
    current_session&.destroy
    cookies.delete(:session_token)
    redirect_to login_path, notice: "Signed out."
  end
end
