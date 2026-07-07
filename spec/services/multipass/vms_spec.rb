# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multipass::Vms, type: :service do
  # Use a Client instance with an injected fake runner.
  let(:logger) { discard_logger }
  def build_client(runner)
    Multipass::Client.new(logger:, runner:)
  end

  # The Go client's parseInfoJSON is private; we exercise it via list_vms
  # which is the only caller. In Ruby we expose it as a private method too —
  # to keep the parity tests tight, we use #send to peek at the parser.
  # Real callers go through list_vms, which is tested below.
  def parse_info(json)
    client = build_client(no_call_runner)
    client.send(:parse_info_json, json)
  end

  # ---- parse_info_json (single VM with all fields populated) ----

  let(:info_json_single_vm) do
    <<~JSON
      {
        "errors": [],
        "info": {
          "test-vm": {
            "state": "Running",
            "image_hash": "abc123",
            "image_release": "24.04 LTS",
            "release": "Ubuntu 24.04.1 LTS",
            "cpu_count": "2",
            "load": [0.5, 0.3, 0.1],
            "disks": {"sda1": {"used": "1073741824", "total": "5368709120"}},
            "memory": {"used": 536870912, "total": 2147483648},
            "mounts": {
              "/home/ubuntu/data": {"source_path": "/host/data", "uid_mappings": ["1000:1000"], "gid_mappings": ["1000:1000"]}
            },
            "ipv4": ["10.0.0.5"],
            "snapshot_count": "1"
          }
        }
      }
    JSON
  end

  let(:info_json_multi_vm) do
    <<~JSON
      {
        "errors": [],
        "info": {
          "vm-b": {"state": "Stopped", "cpu_count": "1", "memory": {"used": 0, "total": 1073741824}, "disks": {}, "mounts": {}, "ipv4": [], "snapshot_count": "0"},
          "vm-a": {"state": "Running", "cpu_count": "4", "memory": {"used": 0, "total": 0}, "disks": {}, "mounts": {}, "ipv4": [], "snapshot_count": "0"}
        }
      }
    JSON
  end

  let(:mixed_state_info) do
    <<~JSON
      {"errors":[],"info":{
        "stopped-a": {"state":"Stopped","cpu_count":"1","memory":{"used":0,"total":0},"disks":{},"mounts":{},"ipv4":[],"snapshot_count":"0"},
        "running-b": {"state":"Running","cpu_count":"1","memory":{"used":0,"total":0},"disks":{},"mounts":{},"ipv4":[],"snapshot_count":"0"},
        "stopped-c": {"state":"Stopped","cpu_count":"1","memory":{"used":0,"total":0},"disks":{},"mounts":{},"ipv4":[],"snapshot_count":"0"}
      }}
    JSON
  end

  describe "#parse_info_json single VM" do
    it "parses all fields correctly" do
      vms = parse_info(info_json_single_vm)
      expect(vms.length).to eq(1)
      vm = vms.first
      expect(vm.name).to eq("test-vm")
      expect(vm.state).to eq("Running")
      expect(vm.cpus).to eq("2")
      expect(vm.load).to eq("0.50 0.30 0.10")
      expect(vm.memory_usage_raw).to eq(536_870_912)
      expect(vm.memory_total_raw).to eq(2_147_483_648)
      expect(vm.memory_usage).to eq("512.0 MiB")
      expect(vm.memory_total).to eq("2.0 GiB")
      expect(vm.snapshots).to eq(1)
      expect(vm.mounts.length).to eq(1)
      expect(vm.mounts.first.target_path).to eq("/home/ubuntu/data")
    end
  end

  describe "#parse_info_json multi VM sorting" do
    it "sorts VMs alphabetically regardless of input order" do
      vms = parse_info(info_json_multi_vm)
      expect(vms.length).to eq(2)
      expect(vms.map(&:name)).to eq(%w[vm-a vm-b])
    end
  end

  # Real-capture regression test: catches drift in multipass output format.
  describe "#parse_info_json with real capture" do
    let(:fixture) { load_fixture("info_all.json") }

    it "parses the captured output identically to the Go client" do
      vms = parse_info(fixture)
      expect(vms.length).to eq(2)

      by_name = vms.to_h { |vm| [ vm.name, vm ] }

      ansible = by_name.fetch("ansible")
      expect(ansible.snapshots).to eq(4)
      expect(ansible.state).to eq("Stopped")
      # Stopped VMs have empty release — parser falls back to image_release.
      expect(ansible.release).to eq("24.04 LTS")

      running = by_name.fetch("undamaged-batfish")
      expect(running.state).to eq("Running")
      expect(running.cpus).to eq("1")
      expect(running.ipv4).to eq([ "192.168.2.134" ])
      expect(running.memory_total_raw).to eq(998_305_792)
      expect(running.snapshots).to eq(0)
    end
  end

  describe "#parse_info_json with malformed JSON" do
    it "raises" do
      expect { parse_info("not json") }.to raise_error(JSON::ParserError)
    end
  end

  # ---- launch_vm argument construction ----

  describe "#launch_vm arg construction" do
    it "builds the canonical argv" do
      runner, calls = fake_runner(
        "launch --name my-vm --cpus 2 --memory 2048M --disk 10G 24.04" => "launched"
      )
      client = build_client(runner)
      name = client.launch_vm(name: "my-vm", release: "24.04", cpus: 2,
                              memory_mb: 2048, disk_gb: 10,
                              cloud_init_file: "", network_name: "")
      expect(name).to eq("my-vm")
      expect(calls.length).to eq(1)
    end

    it "adds --bridged for bridged networking" do
      runner, calls = fake_runner(
        "launch --name v1 --cpus 2 --memory 1024M --disk 8G --bridged 24.04" => "ok"
      )
      build_client(runner).launch_vm(name: "v1", release: "24.04", cpus: 2,
                                     memory_mb: 1024, disk_gb: 8,
                                     cloud_init_file: "", network_name: "bridged")
      expect(calls.first).to include("--bridged")
    end

    it "adds --network <name> for named networking" do
      runner, calls = fake_runner(
        "launch --name v1 --cpus 2 --memory 1024M --disk 8G --network en0 24.04" => "ok"
      )
      build_client(runner).launch_vm(name: "v1", release: "24.04", cpus: 2,
                                     memory_mb: 1024, disk_gb: 8,
                                     cloud_init_file: "", network_name: "en0")
      argv = calls.first
      expect(argv.each_with_index).to include(["--network", argv.index("--network")])
      expect(argv[argv.index("--network") + 1]).to eq("en0")
    end

    it "clamps sub-minimum values to defaults" do
      captured = []
      runner = ->(args) do
        captured.replace(args)
        [ "ok", "", Multipass::SpecHelpers::FakeStatus.success ]
      end
      build_client(runner).launch_vm(name: "vm", release: "", cpus: 0,
                                     memory_mb: 10, disk_gb: 0,
                                     cloud_init_file: "", network_name: "")
      joined = captured.join(" ")
      expect(joined).to include("--cpus 2")
      expect(joined).to include("--memory 1024M")
      expect(joined).to include("--disk 8G")
      expect(joined).to end_with(" 24.04")
    end

    it "rejects flag injection before any subprocess spawn" do
      client = build_client(no_call_runner)
      expect do
        client.launch_vm(name: "--all", release: "24.04", cpus: 2,
                         memory_mb: 1024, disk_gb: 8,
                         cloud_init_file: "", network_name: "")
      end.to raise_error(Multipass::NameValidator::ValidationError, /invalid VM name/)
    end
  end

  # ---- clone_vm ----

  describe "#clone_vm" do
    it "with destination name" do
      runner, calls = fake_runner("clone src --name dst" => "ok")
      build_client(runner).clone_vm("src", dest_name: "dst")
      expect(calls.length).to eq(1)
    end

    it "without destination name" do
      runner, calls = fake_runner("clone src" => "ok")
      build_client(runner).clone_vm("src", dest_name: "")
      expect(calls.length).to eq(1)
    end

    it "rejects invalid source name" do
      expect { build_client(no_call_runner).clone_vm("--all", dest_name: "dst") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end

    it "rejects invalid destination name" do
      expect { build_client(no_call_runner).clone_vm("src", dest_name: "--all") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  # ---- simple lifecycle arg tests ----

  describe "#start_vm" do
    it "builds the start argv" do
      runner, calls = fake_runner("start vm" => "ok")
      build_client(runner).start_vm("vm")
      expect(calls.length).to eq(1)
    end
  end

  describe "#delete_vm" do
    it "with purge" do
      runner, calls = fake_runner("delete vm --purge" => "ok")
      build_client(runner).delete_vm("vm", purge: true)
      expect(calls.first).to include("--purge")
    end

    it "without purge" do
      runner, calls = fake_runner("delete vm" => "ok")
      build_client(runner).delete_vm("vm", purge: false)
      expect(calls.first).not_to include("--purge")
    end

    it "rejects flag injection" do
      expect { build_client(no_call_runner).delete_vm("--all", purge: true) }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#recover_vm" do
    it "rejects invalid name" do
      expect { build_client(no_call_runner).recover_vm("-foo") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  # ---- start_all / stop_all filtering ----

  describe "#start_all" do
    it "starts only stopped VMs" do
      started = []
      runner = ->(args) do
        key = args.join(" ")
        case args.first
        when "info"
          [ mixed_state_info, "", Multipass::SpecHelpers::FakeStatus.success ]
        when "start"
          started << args[1]
          [ "", "", Multipass::SpecHelpers::FakeStatus.success ]
        else
          raise "unexpected: #{key}"
        end
      end
      build_client(runner).start_all
      expect(started.sort).to eq(%w[stopped-a stopped-c])
    end
  end

  describe "#stop_all" do
    it "stops only running VMs" do
      stopped = []
      runner = ->(args) do
        case args.first
        when "info"
          [ mixed_state_info, "", Multipass::SpecHelpers::FakeStatus.success ]
        when "stop"
          stopped << args[1]
          [ "", "", Multipass::SpecHelpers::FakeStatus.success ]
        else
          raise "unexpected: #{args.inspect}"
        end
      end
      build_client(runner).stop_all
      expect(stopped).to eq(%w[running-b])
    end
  end

  # ---- memory / disk parsing ----

  describe "#parse_memory_to_mb" do
    {
      ""              => 0,
      "1073741824"    => 1024,   # bytes
      "1024M"         => 1024,
      "2048m"         => 2048,
      "1G"            => 1024,
      "1g"            => 1024,
      "2.5G"          => 2560,
      "1.0GiB"        => 1024,
      "512MiB"        => 512,
      "1024KiB"       => 1,
      "1T"            => 1024 * 1024,
      "bogus"         => 0
    }.each do |input, expected|
      it "parses #{input.inspect} → #{expected} MB" do
        client = build_client(no_call_runner)
        expect(client.send(:parse_memory_to_mb, input)).to eq(expected)
      end
    end
  end

  describe "#parse_disk_to_gb" do
    {
      ""              => 0,
      "5368709120"    => 5,    # bytes → 5 GB
      "8G"            => 8,
      "8g"            => 8,
      "8.5G"          => 8,
      "8.0GiB"        => 8,
      "1024M"         => 1,
      "1T"            => 1024,
      "bogus"         => 0
    }.each do |input, expected|
      it "parses #{input.inspect} → #{expected} GB" do
        client = build_client(no_call_runner)
        expect(client.send(:parse_disk_to_gb, input)).to eq(expected)
      end
    end
  end

  # ---- get_vm_config with malformed output ----

  describe "#get_vm_config with malformed CLI values" do
    it "yields zeros instead of raising" do
      runner = ->(args) do
        if args.first == "get"
          case args[1]
          when "local.vm.cpus"   then [ "not-a-number", "", Multipass::SpecHelpers::FakeStatus.success ]
          when "local.vm.memory" then [ "garbage",     "", Multipass::SpecHelpers::FakeStatus.success ]
          when "local.vm.disk"   then [ "",            "", Multipass::SpecHelpers::FakeStatus.success ]
          else raise "unexpected key: #{args[1]}"
          end
        else
          raise "unexpected: #{args.inspect}"
        end
      end
      cfg = build_client(runner).get_vm_config("vm")
      expect(cfg.cpus).to eq(0)
      expect(cfg.memory_mb).to eq(0)
      expect(cfg.disk_gb).to eq(0)
    end
  end

  describe "#exec_in_vm rejects flag injection" do
    it "raises before any subprocess spawn" do
      expect { build_client(no_call_runner).exec_in_vm("--all", %w[ls]) }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  # ---- get_vm_info + list_vms paths ----

  describe "#get_vm_info" do
    it "returns the VM" do
      runner, = fake_runner("info test-vm --format json" => info_json_single_vm)
      vm = build_client(runner).get_vm_info("test-vm")
      expect(vm.name).to eq("test-vm")
      expect(vm.state).to eq("Running")
    end

    it "rejects invalid name" do
      expect { build_client(no_call_runner).get_vm_info("--all") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#list_vms with info failure fallback" do
    it "falls back to list --format json when info --all fails" do
      list_json = load_fixture("list.json")
      runner = ->(args) do
        case args.join(" ")
        when "info --all --format json"
          [ "", "no VMs found", Multipass::SpecHelpers::FakeStatus.failure(1) ]
        when "list --format json"
          [ list_json, "", Multipass::SpecHelpers::FakeStatus.success ]
        else
          raise "unexpected: #{args.inspect}"
        end
      end
      vms = build_client(runner).list_vms
      expect(vms.length).to eq(2)
      expect(vms.map(&:name)).to eq(%w[ansible undamaged-batfish])
      expect(vms.last.state).to eq("Running")
      expect(vms.last.ipv4.length).to eq(1)
    end
  end

  # ---- suspend / purge / set_* simple cases ----

  describe "#suspend_vm" do
    it "builds the suspend argv" do
      runner, = fake_runner("suspend vm" => "ok")
      build_client(runner).suspend_vm("vm")
    end

    it "rejects invalid name" do
      expect { build_client(no_call_runner).suspend_vm("--all") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#purge_deleted" do
    it "builds the purge argv" do
      runner, = fake_runner("purge" => "ok")
      build_client(runner).purge_deleted
    end
  end

  describe "#set_vm_cpus" do
    it "builds the set argv" do
      runner, = fake_runner("set local.vm.cpus=4" => "ok")
      build_client(runner).set_vm_cpus("vm", 4)
    end

    it "rejects invalid name" do
      expect { build_client(no_call_runner).set_vm_cpus("--all", 4) }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#set_vm_memory" do
    it "builds the set argv" do
      runner, = fake_runner("set local.vm.memory=2048M" => "ok")
      build_client(runner).set_vm_memory("vm", 2048)
    end
  end

  describe "#set_vm_disk" do
    it "builds the set argv" do
      runner, = fake_runner("set local.vm.disk=20G" => "ok")
      build_client(runner).set_vm_disk("vm", 20)
    end
  end

  # ---- random VM name ----

  describe ".random_vm_name" do
    it "starts with the prefix" do
      expect(Multipass::Client.random_vm_name).to start_with(Multipass::Constants::VM_NAME_PREFIX)
    end
  end

  # ---- format_bytes ----

  describe "#format_bytes" do
    {
      0                      => "0 B",
      1024                   => "1024 B",
      1024 * 1024            => "1.0 MiB",
      5 * 1024 * 1024        => "5.0 MiB",
      1024 * 1024 * 1024     => "1.0 GiB",
      2 * 1024 * 1024 * 1024 => "2.0 GiB"
    }.each do |input, expected|
      it "formats #{input} bytes → #{expected.inspect}" do
        client = build_client(no_call_runner)
        expect(client.send(:format_bytes, input)).to eq(expected)
      end
    end
  end
end
