# frozen_string_literal: true

class Schedule < ApplicationRecord
  self.primary_key = :id_slug

  ACTIONS = %w[start stop playbook].freeze
  DAYS_OF_WEEK = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  validates :id_slug, presence: true, uniqueness: true,
                      format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}\z/ }
  validates :name, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :time, format: { with: /\A[0-2][0-9]:[0-5][0-9]\z/, message: "must be HH:MM" }
  validate :has_targets?

  private

  def has_targets?
    return if group_name.present? || (vm_names.is_a?(Array) && vm_names.any?)
    errors.add(:base, "must have a target group or list of VMs")
  end
end
