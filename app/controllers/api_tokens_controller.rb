# frozen_string_literal: true

class ApiTokensController < ApplicationController
  # GET /api_tokens
  def index
    @tokens = ApiToken.all.order(:name)
    @new_token = flash[:raw_token]
  end

  # POST /api_tokens
  def create
    name = params[:name].presence || raise(ActiveRecord::RecordInvalid, "name required")
    raw = ApiToken.issue!(name:)
    Event.emit_http!(category: "config", action: "create_token",
                     resource: name, result: "success", request: request)
    redirect_to api_tokens_path, flash: { raw_token: raw, notice: "Token created — copy it now (shown once)." }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to api_tokens_path, alert: e.message
  end

  # DELETE /api_tokens/:id
  def destroy
    token = ApiToken.find(params[:id])
    token.destroy
    Event.emit_http!(category: "config", action: "delete_token",
                     resource: token.name, result: "success", request: request)
    redirect_to api_tokens_path, notice: "Revoked #{token.name}."
  end
end
