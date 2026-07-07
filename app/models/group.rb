# frozen_string_literal: true

class Group < ApplicationRecord
  has_many :vm_assignments, dependent: :nullify

  validates :name, presence: true, uniqueness: true,
                   format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9 _-]{0,62}\z/,
                             message: "must start with letter/digit" }

  def self.reorder!(ordered_names)
    transaction do
      ordered_names.each_with_index do |name, idx|
        find_by(name: name)&.update!(position: idx)
      end
    end
  end
end
