# frozen_string_literal: true

# Groups for organising VMs in the tree sidebar — collapsible folders with
# state badges + group context menu. Mirrors Go config.Groups (ordered list).
class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :groups, :name, unique: true
    add_index :groups, :position
  end
end
