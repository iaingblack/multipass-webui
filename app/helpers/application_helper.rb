# frozen_string_literal: true

module ApplicationHelper
  def vm_counts
    counts = { "Running" => 0, "Stopped" => 0, "Suspended" => 0, "Deleted" => 0 }
    @vms.each { |vm| counts[vm.state] = (counts[vm.state] || 0) + 1 }
    counts
  end

  def host_total_memory_gb
    (@host_resources&.total_memory_mb || 0) / 1024.0
  end

  def host_used_memory_gb
    (@host_resources&.used_memory_mb || 0) / 1024.0
  end

  def host_total_disk_gb
    (@host_resources&.total_disk_mb || 0) / 1024.0
  end

  def host_used_disk_gb
    (@host_resources&.used_disk_mb || 0) / 1024.0
  end
end
