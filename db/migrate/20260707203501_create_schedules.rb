# frozen_string_literal: true

# Scheduled operations — start/stop VMs or run playbooks on a schedule.
# Mirrors Go's Schedule struct (internal/config/config.go:92-102).
class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.string :id_slug, null: false
      t.string :name, null: false
      t.boolean :enabled, default: true
      t.string :action, null: false    # start|stop|playbook
      t.string :time, null: false      # HH:MM
      t.json :days                     # [0..6] (0=Sunday)
      t.string :target_mode            # vms|group
      t.json :vm_names
      t.string :group_name
      t.string :playbook
      t.datetime :last_fired_at        # double-fire prevention

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :schedules, :id_slug, unique: true
  end
end
