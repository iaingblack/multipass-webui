# frozen_string_literal: true

class WebhooksController < ApplicationController
  def index
    @webhooks = Webhook.all.order(:name)
  end

  def new
    @webhook = Webhook.new(enabled: true, categories: [], results: [])
  end

  def create
    @webhook = Webhook.new(webhook_params.merge(id_slug: generate_id_slug))
    if @webhook.save
      Event.emit_http!(category: "config", action: "create_webhook",
                       resource: @webhook.id_slug, result: "success", request: request)
      redirect_to webhooks_path, notice: "Created #{@webhook.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @webhook = Webhook.find(params[:id])
  end

  def update
    @webhook = Webhook.find(params[:id])
    # Preserve existing secret if not provided (matches Go behavior at
    # handlers_webhooks.go:104-106).
    updates = webhook_params
    updates.delete(:secret) if updates[:secret].blank? && @webhook.secret.present?
    if @webhook.update(updates)
      Event.emit_http!(category: "config", action: "update_webhook",
                       resource: @webhook.id_slug, result: "success", request: request)
      redirect_to webhooks_path, notice: "Updated #{@webhook.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    webhook = Webhook.find(params[:id])
    webhook.destroy
    Event.emit_http!(category: "config", action: "delete_webhook",
                     resource: webhook.id_slug, result: "success", request: request)
    redirect_to webhooks_path, notice: "Deleted #{webhook.name}."
  end

  # POST /webhooks/:id/test — fire a sample event
  def test
    webhook = Webhook.find(params[:id])
    test_event = Event.new(
      category: "test", action: "test", actor: "user",
      resource: webhook.name, result: "success"
    )
    result = webhook.deliver(test_event)
    redirect_to webhooks_path,
                notice: "Test delivery: #{result}"
  end

  private

  def webhook_params
    p = params.require(:webhook).permit(:name, :url, :enabled, :secret,
                                        categories: [], results: [])
    p[:categories] = (p[:categories] || []).select(&:present?)
    p[:results] = (p[:results] || []).select(&:present?)
    p
  end

  def generate_id_slug
    "wh_#{SecureRandom.hex(4)}"
  end
end
