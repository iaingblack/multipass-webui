# frozen_string_literal: true

# Singleton VM defaults — applied when creating a VM without explicit values.
# Mirrors internal/config/config.go VMDefaults struct.
class CreateVmDefaults < ActiveRecord::Migration[8.1]
  def change
    create_table :vm_defaults do |t|
      t.integer :cpus, null: false, default: 2
      t.integer :memory_mb, null: false, default: 1024
      t.integer :disk_gb, null: false, default: 8
      t.text :ssh_public_key
      t.text :ssh_private_key

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
