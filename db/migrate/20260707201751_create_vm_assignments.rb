# frozen_string_literal: true

# Tracks which group each VM belongs to. Mirrors Go config.VMGroups map
# (vm_name → group_name). VM name is unique: a VM can only be in one group.
# Also carries the is_template flag — VMs protected from mutation.
class CreateVmAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :vm_assignments do |t|
      t.string :vm_name, null: false
      t.references :group, foreign_key: true
      t.boolean :is_template, null: false, default: false

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :vm_assignments, :vm_name, unique: true
  end
end
