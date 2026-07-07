# frozen_string_literal: true

module Multipass
  # Defaults and limits mirrored from the upstream Go multipass wrapper.
  # These values are referenced by the client and surfaced in the create-VM
  # forms, so they live here as the single source of truth.
  module Constants
    DEFAULT_UBUNTU_RELEASE = "24.04"
    DEFAULT_CPU_CORES = 2
    DEFAULT_RAM_MB = 1024
    DEFAULT_DISK_GB = 8
    MIN_CPU_CORES = 1
    MIN_RAM_MB = 512
    MIN_RESIZE_RAM_MB = 256
    MIN_DISK_GB = 1
    VM_NAME_PREFIX = "VM-"
    VM_NAME_RANDOM_LENGTH = 4

    UBUNTU_RELEASES = %w[24.04 22.04 20.04 18.04 daily].freeze
  end
end
