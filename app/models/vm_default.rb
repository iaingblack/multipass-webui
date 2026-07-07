# frozen_string_literal: true

# Singleton VM defaults — applied when creating a VM without explicit values.
# Mirrors VMDefaults struct from Go internal/config/config.go:38-44.
class VmDefault < ApplicationRecord
  def self.current
    first || create!(cpus: 2, memory_mb: 1024, disk_gb: 8)
  end
end
