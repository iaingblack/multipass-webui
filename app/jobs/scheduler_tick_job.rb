# frozen_string_literal: true

# Scheduler tick — runs every 30 seconds via SolidQueue recurring.
# Matches Go's scheduler.go:56-68 ticker behaviour:
#   - Snapshots enabled schedules
#   - For each: checks timeMatches (exact HH:MM match + day-of-week)
#   - Prevents double-fire within the same minute via last_fired_at
#   - Executes start/stop/playbook action on target VMs
#
# Configured in config/recurring.yml.
class SchedulerTickJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    schedules = Schedule.where(enabled: true).to_a
    return if schedules.empty?

    vms_by_group = nil # lazy — only resolved if a group-targeted schedule fires

    schedules.each do |sched|
      next unless time_matches?(sched, now)
      next if already_fired_this_minute?(sched, now)

      sched.update!(last_fired_at: now)
      targets = resolve_targets(sched)
      if targets.empty?
        Event.emit!(category: "schedule", action: "tick", actor: "scheduler",
                    resource: sched.name, result: "no_targets",
                    detail: "no VMs matched")
        next
      end

      result = execute(sched, targets)
      Event.emit!(category: "schedule", action: sched.action, actor: "scheduler",
                  resource: sched.name, result: result,
                  detail: "targets: #{targets.join(', ')}")
    end
  end

  private

  # Exact minute match + day-of-week. Same as Go's timeMatches at scheduler.go:99-121.
  def time_matches?(sched, now)
    hour, min = sched.time.split(":").map(&:to_i)
    return false if now.hour != hour || now.min != min
    return true if sched.days.blank? || sched.days.empty?
    sched.days.include?(now.wday)
  end

  # Prevents double-fire within the same minute — matches Go's lastFire map.
  # last_fired_at is now persisted in the DB (improvement over Go's in-memory map).
  def already_fired_this_minute?(sched, now)
    return false unless sched.last_fired_at
    sched.last_fired_at.min == now.min &&
      sched.last_fired_at.hour == now.hour &&
      sched.last_fired_at.day == now.day
  end

  def resolve_targets(sched)
    if sched.group_name.present?
      VmAssignment.where(group_id: Group.find_by(name: sched.group_name)).pluck(:vm_name)
    else
      sched.vm_names || []
    end
  end

  def execute(sched, targets)
    client = Multipass::Client.new
    errors = []

    case sched.action
    when "start"
      targets.each { |name| client.start_vm(name) rescue errors << "#{name}: #{$!.message}" }
    when "stop"
      targets.each { |name| client.stop_vm(name) rescue errors << "#{name}: #{$!.message}" }
    when "playbook"
      # Enqueue playbook run (Phase 5 will wire AnsibleRunJob)
      Rails.logger.info("[scheduler] playbook run #{sched.playbook} on #{targets.inspect} — deferred to Phase 5")
      return "success"
    end

    return "success" if errors.empty?
    return "partial" if errors.length < targets.length
    "failed"
  end
end
