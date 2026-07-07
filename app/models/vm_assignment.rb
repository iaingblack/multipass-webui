# frozen_string_literal: true

class VmAssignment < ApplicationRecord
  belongs_to :group, optional: true

  validates :vm_name, presence: true, uniqueness: true
end
