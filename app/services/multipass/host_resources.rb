# frozen_string_literal: true

require "open3"
require "pathname"

module Multipass
  # Platform-aware host resource detection. Mirrors the per-OS Go files
  # (host_darwin.go / host_linux.go / host_windows.go) using Ruby's
  # +RbConfig::CONFIG["host_os"]+ dispatch instead of build tags.
  module HostResources
    module_function

    # Returns +Types::HostResources+ populated for the current host.
    # Errors from individual collectors (load avg, memory, disk) are
    # accumulated into an array returned as the second value so callers
    # can log partial failures without losing the rest of the data.
    def get
      collector = case RbConfig::CONFIG["host_os"]
                  when /darwin/  then DarwinCollector
                  when /linux/   then LinuxCollector
                  when /mswin|mingw|windows/ then WindowsCollector
                  else                NullCollector
                  end
      collector.get
    end

    # -- per-OS collectors ------------------------------------------------

    module DarwinCollector
      module_function

      def get
        res = Types::HostResources.new(total_cpus: Etc.nprocessors)
        errors = []

        mem_bytes = parse_int_from_cmd("sysctl", "-n", "hw.memsize")
        res.total_memory_mb = mem_bytes / (1024 * 1024) if mem_bytes

        load1, load5, load15 = parse_loadavg_darwin
        if load1
          res.load_avg_1 = load1
          res.load_avg_5 = load5
          res.load_avg_15 = load15
        else
          errors << "loadavg: parse failed"
        end

        if (used = parse_mem_usage_darwin)
          res.used_memory_mb = used
        else
          errors << "vm_stat: parse failed"
        end

        total, used = parse_disk_usage_darwin
        if total
          res.total_disk_mb = total
          res.used_disk_mb = used
        else
          errors << "disk: parse failed"
        end

        [ res, errors ]
      end

      def parse_loadavg_darwin
        out, _, status = Open3.capture3("sysctl", "-n", "vm.loadavg")
        return nil unless status.success?
        # Output: "{ 0.45 0.52 0.48 }"
        s = out.strip.gsub(/[{}]/, "")
        parts = s.split
        return nil unless parts.length >= 3
        parts.first(3).map(&:to_f)
      rescue StandardError
        nil
      end

      def parse_mem_usage_darwin
        out, _, status = Open3.capture3("vm_stat")
        return nil unless status.success?
        page_size = 4096 # macOS default
        active = wired = compressed = 0
        out.each_line do |line|
          line = line.strip
          if line.start_with?("Pages active:")
            active = parse_vm_stat_value(line)
          elsif line.start_with?("Pages wired down:")
            wired = parse_vm_stat_value(line)
          elsif line.start_with?("Pages occupied by compressor:")
            compressed = parse_vm_stat_value(line)
          end
        end
        ((active + wired + compressed) * page_size) / (1024 * 1024)
      rescue StandardError
        nil
      end

      def parse_vm_stat_value(line)
        _, value = line.split(":", 2)
        return 0 if value.nil?
        value.strip.sub(".", "").to_i
      end

      def parse_disk_usage_darwin
        # On APFS, "/" is read-only; user data lives on /System/Volumes/Data
        path = "/System/Volumes/Data"
        out, _, status = Open3.capture3("df", "-k", path)
        unless status.success?
          out, _, status = Open3.capture3("df", "-k", "/")
          return [ nil, nil ] unless status.success?
        end
        fields = out.strip.split("\n").last&.split
        return [ nil, nil ] if fields.nil? || fields.length < 4
        [ fields[1].to_i / 1024, fields[2].to_i / 1024 ]
      rescue StandardError
        [ nil, nil ]
      end

      def parse_int_from_cmd(*cmd)
        out, _, status = Open3.capture3(*cmd)
        return nil unless status.success?
        out.strip.to_i
      rescue StandardError
        nil
      end
    end

    module LinuxCollector
      module_function

      def get
        res = Types::HostResources.new(total_cpus: Etc.nprocessors)
        errors = []

        load1, load5, load15 = parse_loadavg_linux
        if load1
          res.load_avg_1 = load1
          res.load_avg_5 = load5
          res.load_avg_15 = load15
        else
          errors << "loadavg: parse failed"
        end

        total, used = parse_meminfo_linux
        if total
          res.total_memory_mb = total
          res.used_memory_mb = used
        else
          errors << "meminfo: parse failed"
        end

        total, used = parse_disk_usage_linux
        if total
          res.total_disk_mb = total
          res.used_disk_mb = used
        else
          errors << "disk: parse failed"
        end

        [ res, errors ]
      end

      def parse_loadavg_linux
        data = File.read("/proc/loadavg")
        parts = data.split
        return nil unless parts.length >= 3
        parts.first(3).map(&:to_f)
      rescue StandardError
        nil
      end

      def parse_meminfo_linux
        total_kb = available_kb = 0
        File.foreach("/proc/meminfo") do |line|
          if line.start_with?("MemTotal:")
            total_kb = line.split[1].to_i
          elsif line.start_with?("MemAvailable:")
            available_kb = line.split[1].to_i
          end
        end
        return nil if total_kb.zero?
        [ total_kb / 1024, (total_kb - available_kb) / 1024 ]
      rescue StandardError
        nil
      end

      def parse_disk_usage_linux
        out, _, status = Open3.capture3("df", "-k", "/")
        return [ nil, nil ] unless status.success?
        fields = out.strip.split("\n").last&.split
        return [ nil, nil ] if fields.nil? || fields.length < 4
        [ fields[1].to_i / 1024, fields[2].to_i / 1024 ]
      rescue StandardError
        [ nil, nil ]
      end
    end

    module WindowsCollector
      module_function

      def get
        res = Types::HostResources.new(total_cpus: Etc.nprocessors)
        [ res, %w[windows host-resources not implemented] ]
      end
    end

    module NullCollector
      module_function

      def get
        [ Types::HostResources.new(total_cpus: Etc.nprocessors),
          [ "unsupported host OS: #{RbConfig::CONFIG['host_os']}" ] ]
      end
    end
  end
end
