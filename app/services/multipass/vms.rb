# frozen_string_literal: true

require "json"
require "fileutils"
require "tempfile"

module Multipass
  # Mixed into +Multipass::Client+. All VM lifecycle operations (list, info,
  # start/stop/suspend/delete/recover, launch, clone, exec, config get/set,
  # cloud-init status) live here. Each method that takes a VM name calls
  # +NameValidator.validate_vm_name!+ before delegating to +#run+.
  module Vms
    # List all VMs with full details. Falls back to +list --format json+
    # (which returns less detail) if +info --all+ fails — that happens when
    # no VMs exist yet.
    def list_vms
      output = run("info", "--all", "--format", "json")
      parse_info_json(output)
    rescue Client::CommandError => e
      # Try the lighter list endpoint before giving up.
      begin
        list_output = run("list", "--format", "json")
      rescue Client::CommandError
        raise e
      end
      vms = parse_list_json_basic(list_output)
      vms.sort_by(&:name)
    end

    # Get details for a single VM.
    def get_vm_info(name)
      NameValidator.validate_vm_name!(name)
      output = run("info", name, "--format", "json")
      vms = parse_info_json(output)
      vms.find { |vm| vm.name == name } or
        raise ArgumentError, "VM #{name.inspect} not found in info response"
    end

    # Launch a new VM. Returns the resolved name (generated if blank).
    # Defaults applied for missing/under-minimum values, matching the Go
    # client behaviour: blank → default, < min → default (not min).
    def launch_vm(name:, release:, cpus:, memory_mb:, disk_gb:, cloud_init_file:, network_name:)
      name = Client.random_vm_name if name.nil? || name.empty?
      NameValidator.validate_vm_name!(name)

      release = Constants::DEFAULT_UBUNTU_RELEASE if release.nil? || release.empty?
      cpus    = Constants::DEFAULT_CPU_CORES       if cpus.nil?    || cpus.to_i  < Constants::MIN_CPU_CORES
      memory_mb = Constants::DEFAULT_RAM_MB        if memory_mb.nil? || memory_mb.to_i < Constants::MIN_RAM_MB
      disk_gb = Constants::DEFAULT_DISK_GB         if disk_gb.nil?  || disk_gb.to_i  < Constants::MIN_DISK_GB

      args = %W[launch --name #{name} --cpus #{cpus.to_i} --memory #{memory_mb.to_i}M --disk #{disk_gb.to_i}G]

      unless cloud_init_file.nil? || cloud_init_file.empty?
        # Snap-confined multipass can't read paths outside its confinement
        # (e.g. /root/). Copy to a location it can read; fall back to the
        # system temp dir if the snap common path doesn't exist.
        tmp_file = copy_for_snap(cloud_init_file)
        args += %W[--cloud-init #{tmp_file}]
      end

      case network_name
      when nil, "", "nat"
        # default — no flag
      when "bridged"
        args << "--bridged"
      else
        args += %W[--network #{network_name}]
      end

      args << release
      begin
        run(*args)
      ensure
        # cloud-init temp file is cleaned up regardless of launch outcome
        FileUtils.rm_f(@last_cloud_init_tmp) if defined?(@last_cloud_init_tmp)
      end
      name
    end

    # Clone a stopped VM. Returns the destination name (multipass
    # auto-generates one if +dest_name+ is blank — we return whatever was
    # passed in, so callers tracking by name should pass a non-blank name).
    def clone_vm(source, dest_name: nil)
      NameValidator.validate_vm_name!(source)
      NameValidator.validate_vm_name!(dest_name) if dest_name && !dest_name.empty?

      args = %W[clone #{source}]
      args += %W[--name #{dest_name}] if dest_name && !dest_name.empty?
      run(*args)
      dest_name
    end

    def start_vm(name)
      NameValidator.validate_vm_name!(name)
      run("start", name)
    end

    def stop_vm(name)
      NameValidator.validate_vm_name!(name)
      run("stop", name)
    end

    def suspend_vm(name)
      NameValidator.validate_vm_name!(name)
      run("suspend", name)
    end

    def delete_vm(name, purge: false)
      NameValidator.validate_vm_name!(name)
      args = %W[delete #{name}]
      args << "--purge" if purge
      run(*args)
    end

    def recover_vm(name)
      NameValidator.validate_vm_name!(name)
      run("recover", name)
    end

    def purge_deleted
      run("purge")
    end

    # Start every VM in the given state. Aggregates per-VM errors into one
    # message rather than failing on the first error.
    def start_all = run_all_in_state("Stopped") { |name| start_vm(name) }
    def stop_all  = run_all_in_state("Running") { |name| stop_vm(name) }

    # Run a command inside a VM, returning stdout. +command+ is an argv
    # array — never a shell string. Multipass joins it with "--".
    def exec_in_vm(vm_name, command)
      NameValidator.validate_vm_name!(vm_name)
      run("exec", vm_name, "--", *command)
    end

    # Get configured CPU/memory/disk for a VM (available even when stopped).
    def get_vm_config(name)
      NameValidator.validate_vm_name!(name)
      cpu_str  = run("get", "local.#{name}.cpus")
      mem_str  = run("get", "local.#{name}.memory")
      disk_str = run("get", "local.#{name}.disk")
      Types::VmConfig.new(
        cpus:      cpu_str.strip.to_i,
        memory_mb: parse_memory_to_mb(mem_str),
        disk_gb:   parse_disk_to_gb(disk_str)
      )
    end

    def set_vm_cpus(name, cpus)
      NameValidator.validate_vm_name!(name)
      run("set", "local.#{name}.cpus=#{cpus.to_i}")
    end

    def set_vm_memory(name, memory_mb)
      NameValidator.validate_vm_name!(name)
      run("set", "local.#{name}.memory=#{memory_mb.to_i}M")
    end

    def set_vm_disk(name, disk_gb)
      NameValidator.validate_vm_name!(name)
      run("set", "local.#{name}.disk=#{disk_gb.to_i}G")
    end

    def get_raw_info(name)
      NameValidator.validate_vm_name!(name)
      run("info", name)
    end

    # Check cloud-init status inside a running VM. Always returns a
    # +CloudInitStatus+; never raises on cloud-init's own exit codes
    # (it uses 0=running/done, 1=fatal, 2=recoverable — all valid states
    # with useful stdout, captured via "sh -c '...; exit 0'").
    def get_cloud_init_status(vm_name)
      result = Types::CloudInitStatus.new(status: "pending", detail: "Waiting for VM to be ready...")
      NameValidator.validate_vm_name!(vm_name)

      json_output =
        begin
          run("exec", vm_name, "--", "sh", "-c", "cloud-init status --format json 2>/dev/null; exit 0")
        rescue Client::CommandError
          # exec itself failed (VM not ready for SSH yet) — return pending
          return result
        end

      if json_output && !json_output.strip.empty?
        parsed = JSON.parse(json_output) rescue {}
        status = parsed["extended_status"].presence || parsed["status"] || result.status
        result = Types::CloudInitStatus.new(
          status:,
          detail: parsed["detail"],
          errors: parsed["errors"] || []
        )
      end

      # Best-effort: tail last 50 lines of the cloud-init output log
      log_output =
        begin
          run("exec", vm_name, "--", "sh", "-c", "tail -n 50 /var/log/cloud-init-output.log 2>/dev/null; exit 0")
        rescue Client::CommandError
          ""
        end
      result.output = log_output unless log_output.nil? || log_output.empty?
      result
    end

    private

    # Iterate every VM in +state+ and call the block on it. Collects per-VM
    # errors into one aggregate +CommandError+ so a single failing VM
    # doesn't mask the success of the others.
    def run_all_in_state(state, &block)
      vms = list_vms
      errors = []
      vms.each do |vm|
        next unless vm.state == state
        block.call(vm.name)
      rescue Client::CommandError => e
        errors << "#{vm.name}: #{e.message}"
      end
      return if errors.empty?

      raise Client::CommandError.new(%w[bulk], FakeStatusForAggregate.failure,
                                     "", errors.join("; "))
    end

    def parse_info_json(output)
      resp = JSON.parse(output)
      info = resp.fetch("info", {})
      vms = info.map do |name, detail|
        # Stopped VMs return an empty "release" but populate "image_release"
        # — fall back so the UI shows something useful.
        release = detail["release"].presence || detail["image_release"].to_s

        # snapshot_count comes back as a string ("4"). Parse failures fall
        # through to 0 — the field is cosmetic, not worth bubbling up.
        snapshot_count = detail["snapshot_count"].to_s.strip.to_i

        vm = Types::VmInfo.new(
          name:,
          state: detail["state"],
          ipv4: detail["ipv4"] || [],
          release:,
          image_hash: detail["image_hash"],
          cpus: detail["cpu_count"],
          snapshots: snapshot_count
        )

        load_arr = detail["load"]
        if load_arr.is_a?(Array) && load_arr.length == 3
          vm.load = format("%<one>.2f %<five>.2f %<fifteen>.2f",
                           one: load_arr[0], five: load_arr[1], fifteen: load_arr[2])
        end

        detail["disks"]&.each_value do |disk|
          if (used = disk["used"].to_s.strip.to_i) > 0
            vm.disk_usage_raw = used
            vm.disk_usage = format_bytes(used)
          end
          if (total = disk["total"].to_s.strip.to_i) > 0
            vm.disk_total_raw = total
            vm.disk_total = format_bytes(total)
          end
          break # only one disk per VM in current multipass
        end

        used  = detail.fetch("memory", {}).fetch("used", 0).to_i
        total = detail.fetch("memory", {}).fetch("total", 0).to_i
        vm.memory_usage_raw = used
        vm.memory_total_raw = total
        vm.memory_usage = format_bytes(used)
        vm.memory_total = format_bytes(total)

        detail["mounts"]&.each do |target, mount|
          vm.mounts << Types::MountInfo.new(
            source_path: mount["source_path"],
            target_path: target,
            uid_maps: mount["uid_mappings"] || [],
            gid_maps: mount["gid_mappings"] || []
          )
        end
        vm.mounts.sort_by!(&:target_path)

        vm
      end
      vms.sort_by(&:name)
    end

    def parse_list_json_basic(output)
      resp = JSON.parse(output)
      resp.fetch("list", []).map do |v|
        Types::VmInfo.new(
          name: v["name"],
          state: v["state"],
          ipv4: v["ipv4"] || [],
          release: v["release"]
        )
      end
    end

    def copy_for_snap(src_path)
      data = File.binread(src_path)
      snap_dir = "/var/snap/multipass/common"
      dir = File.exist?(snap_dir) ? snap_dir : Dir.tmpdir
      dst = File.join(dir, "passgo-cloud-init-#{File.basename(src_path)}")
      File.binwrite(dst, data)
      @last_cloud_init_tmp = dst
      dst
    end

    def format_bytes(bytes)
      mb = 1024 * 1024
      gb = 1024 * 1024 * 1024
      case bytes
      when gb..    then format("%.1f GiB", bytes.to_f / gb)
      when mb..    then format("%.1f MiB", bytes.to_f / mb)
      else              "#{bytes} B"
      end
    end

    def strip_unit_suffix(s)
      # Handle GiB/MiB/KiB/TiB (e.g. "1.0GiB")
      %w[GiB MiB KiB TiB GB MB KB TB].each do |suffix|
        if s.end_with?(suffix)
          return [ s[0...-suffix.length], suffix[0] ]
        end
      end
      # Single-letter suffixes (G, M, K, T)
      return [ s[0...-1], s[-1] ] if s.length > 1 && s[-1].match?(/[GgMmKkTt]/)
      # Plain number = bytes
      [ s, "B" ]
    end

    def parse_memory_to_mb(s)
      s = s.to_s.strip
      return 0 if s.empty?
      num, unit = strip_unit_suffix(s)
      case unit.downcase
      when "g" then (num.to_f * 1024).to_i
      when "m" then num.to_f.to_i
      when "k" then (num.to_f / 1024).to_i
      when "t" then (num.to_f * 1024 * 1024).to_i
      else          num.to_i / (1024 * 1024)
      end
    end

    def parse_disk_to_gb(s)
      s = s.to_s.strip
      return 0 if s.empty?
      num, unit = strip_unit_suffix(s)
      case unit.downcase
      when "g" then num.to_f.to_i
      when "m" then (num.to_f / 1024).to_i
      when "t" then (num.to_f * 1024).to_i
      else          num.to_i / (1024 * 1024 * 1024)
      end
    end

    # Status object for aggregated bulk failures — preserves the
    # +Multipass::Client::CommandError+ shape without invoking a real
    # subprocess.
    class FakeStatusForAggregate
      def self.failure = new
      def success? = false
      def exitstatus = 1
    end
  end
end
