# frozen_string_literal: true

module Multipass
  # Plain value objects representing data returned by the multipass CLI.
  # These are read-only structs — they carry no behaviour beyond what's
  # needed for serialization and display. Not ActiveRecord models.
  module Types
    # Full details about a virtual machine.
    VmInfo = Struct.new(
      :name, :state, :snapshots, :ipv4, :release, :image_hash,
      :cpus, :load, :disk_usage, :disk_total,
      :memory_usage, :memory_total,
      :memory_usage_raw, :memory_total_raw,
      :disk_usage_raw, :disk_total_raw,
      :mounts,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.snapshots ||= 0
        self.ipv4 ||= []
        self.mounts ||= []
      end
    end

    # A snapshot of a VM at a point in time.
    # +created+ is an RFC3339 timestamp parsed from multipass's locale-dependent
    # human-readable form (see Snapshots.parse_multipass_created); +nil+ if parsing failed.
    SnapshotInfo = Struct.new(
      :instance, :name, :parent, :comment, :created, :children,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.children ||= []
      end
    end

    # A mount point between a host path and a VM target.
    MountInfo = Struct.new(
      :source_path, :target_path, :uid_maps, :gid_maps,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.uid_maps ||= []
        self.gid_maps ||= []
      end
    end

    # An available host network interface for bridged networking.
    NetworkInfo = Struct.new(:name, :type, :description, keyword_init: true)

    # A selectable cloud-init template shown in the create-VM picker.
    TemplateOption = Struct.new(:label, :path, :built_in, keyword_init: true) do
      def initialize(**)
        super
        self.built_in = false if built_in.nil?
      end
    end

    # An available image or blueprint from `multipass find`.
    ImageInfo = Struct.new(
      :name, :aliases, :os, :release, :remote, :version, :type,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.aliases ||= []
        self.type ||= "image"
      end
    end

    # Configured (not runtime) resource specs for a VM.
    # Available even when the VM is stopped (unlike VmInfo).
    VmConfig = Struct.new(:cpus, :memory_mb, :disk_gb, keyword_init: true)

    # Status of cloud-init inside a running VM.
    CloudInitStatus = Struct.new(:status, :detail, :errors, :output, keyword_init: true) do
      def initialize(**)
        super
        self.errors ||= []
      end
    end

    # Host machine resource capacity and current usage.
    HostResources = Struct.new(
      :total_cpus, :load_avg_1, :load_avg_5, :load_avg_15,
      :total_memory_mb, :used_memory_mb,
      :total_disk_mb, :used_disk_mb,
      keyword_init: true
    )
  end
end
