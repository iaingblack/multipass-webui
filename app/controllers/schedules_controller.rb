# frozen_string_literal: true

class SchedulesController < ApplicationController
  def index
    @schedules = Schedule.all.order(:name)
  end

  def new
    @schedule = Schedule.new(
      enabled: true,
      action: "start",
      time: "09:00",
      days: [ 1, 2, 3, 4, 5 ],
      target_mode: "vms",
      vm_names: []
    )
  end

  def create
    @schedule = Schedule.new(schedule_params.merge(id_slug: generate_id_slug))
    if @schedule.save
      Event.emit_http!(category: "schedule", action: "create_schedule",
                       resource: @schedule.id_slug, result: "success", request: request)
      redirect_to schedules_path, notice: "Created #{@schedule.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @schedule = Schedule.find(params[:id])
  end

  def update
    @schedule = Schedule.find(params[:id])
    if @schedule.update(schedule_params)
      Event.emit_http!(category: "schedule", action: "update_schedule",
                       resource: @schedule.id_slug, result: "success", request: request)
      redirect_to schedules_path, notice: "Updated #{@schedule.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    schedule = Schedule.find(params[:id])
    schedule.destroy
    Event.emit_http!(category: "schedule", action: "delete_schedule",
                     resource: schedule.id_slug, result: "success", request: request)
    redirect_to schedules_path, notice: "Deleted #{schedule.name}."
  end

  private

  def schedule_params
    p = params.require(:schedule).permit(:name, :enabled, :action, :time,
                                         :target_mode, :group_name, :playbook, days: [], vm_names: [])
    p[:days] = (p[:days] || []).map(&:to_i) if p[:days]
    p[:vm_names] = (p[:vm_names] || []).select(&:present?) if p[:vm_names]
    p
  end

  def generate_id_slug
    "sch_#{SecureRandom.hex(8)}"
  end
end
