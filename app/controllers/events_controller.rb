# frozen_string_literal: true

class EventsController < ApplicationController
  # GET /events
  def index
    @events = Event.order(created_at: :desc).limit(50)
    @events = @events.where(category: params[:category])       if params[:category].present?
    @events = @events.where(actor: params[:actor])             if params[:actor].present?
    @events = @events.where(resource: params[:resource])       if params[:resource].present?
    @events = @events.where("created_at >= ?", params[:since]) if params[:since].present?

    respond_to do |format|
      format.html
      format.json { render json: @events }
    end
  end
end
