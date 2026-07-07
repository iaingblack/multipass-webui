# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  # Most routes require auth. Override with `skip_before_action :require_login`.
  before_action :require_login

  helper_method :current_setting, :logged_in?

  # Reject if no valid session. Skip for the login form itself + health checks.
  def require_login
    return if logged_in?

    respond_to do |format|
      format.html { redirect_to login_path, alert: "Please sign in to continue." }
      format.json { render json: { error: "authentication required" }, status: :unauthorized }
      format.turbo_stream { render json: { error: "authentication required" }, status: :unauthorized }
    end
  end

  def logged_in?
    current_session.present?
  end

  # The current valid session row, or nil. Memoized per request.
  def current_session
    return @current_session if defined?(@current_session)
    @current_session = Session.find_valid(cookies.signed[:session_token])
  end

  # Single shared settings row. Memoized per request.
  def current_setting
    @current_setting ||= Setting.current
  end

  # Convenience accessor for views: the multipass client.
  def multipass
    @multipass ||= Multipass::Client.new
  end
end
