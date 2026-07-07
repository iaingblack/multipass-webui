# frozen_string_literal: true

require "json"
require "time"

module Multipass
  module Snapshots
    # Layouts multipass has been observed to use for the snapshot "created"
    # field. Multipass varies by locale/version — observed so far:
    #   - "Thu Apr 16 20:52:52 2026 BST"   (ANSIC + zone, month before day)
    #   - "Thu 16 Apr 20:52:52 2026 BST"   (day before month)
    # We try each in turn; if none match, the raw string is passed through
    # so the frontend can still display something rather than losing the data.
    MULTIPASS_CREATED_LAYOUTS = [
      "%a %b %e %H:%M:%S %Y %Z",   # ANSIC + zone, month before day
      "%a %e %b %H:%M:%S %Y %Z",  # day before month
      "%a %e %b %Y %H:%M:%S %Z",
      "%Y-%m-%dT%H:%M:%S%z",       # RFC3339
    ].freeze

    # Ruby's +Time.parse+ (and Go's +time.Parse+) only resolve zone
    # abbreviations from the host's local tzdata — a UTC-only Linux server
    # parsing "BST" gets offset 0, silently dropping the hour adjustment.
    # This table is consulted to rewrite the instant when +Time.parse+
    # returns a fabricated zero-offset zone.
    KNOWN_ZONE_OFFSETS = {
      "UTC" => 0, "GMT" => 0, "Z" => 0,
      "BST" => 3600, "IST" => 3600, "WEST" => 3600, "WET" => 0,
      "CET" => 3600, "CEST" => 7200,
      "EET" => 7200, "EEST" => 10800,
      "MSK" => 10800,
      "EST" => -18000, "EDT" => -14400,
      "CST" => -21600, "CDT" => -18000,
      "MST" => -25200, "MDT" => -21600,
      "PST" => -28800, "PDT" => -25200,
      "AKST" => -32400, "AKDT" => -28800,
      "HST" => -36000,
      "AEST" => 36000, "AEDT" => 39600,
      "JST" => 32400, "KST" => 32400,
      "SGT" => 28800, "HKT" => 28800
    }.freeze

    module_function

    # Parse a "created" timestamp from multipass into RFC3339 UTC.
    # Returns the raw string verbatim if no layout matches.
    def parse_multipass_created(raw)
      return "" if raw.nil? || raw.empty?
      MULTIPASS_CREATED_LAYOUTS.each do |layout|
        begin
          t = Time.strptime(raw, layout)
        rescue ArgumentError
          next
        end
        # Rewrite zero-offset zone abbreviations using our table.
        zone_name = t.zone
        if t.utc_offset.zero? && zone_name && zone_name != "UTC"
          if (real = KNOWN_ZONE_OFFSETS[zone_name])
            t = t - real
          end
        end
        return t.getutc.iso8601
      rescue ArgumentError
        next
      end
      raw
    end

    # Refinements to expose parse_multipass_created via Client.include?.
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      # Returns snapshots for a VM, including created timestamps and child
      # arrays. Uses +info --snapshots+ (richer than +list --snapshots+,
      # which only returns parent + comment).
      def list_snapshots(vm_name)
        NameValidator.validate_vm_name!(vm_name)
        output = run("info", vm_name, "--snapshots", "--format", "json")
        resp = JSON.parse(output)
        vm = resp.fetch("info", {}).fetch(vm_name, {})
        snaps = vm.fetch("snapshots", {})
        return [] if snaps.empty?

        snaps.map do |name, entry|
          Types::SnapshotInfo.new(
            instance: vm_name,
            name:,
            parent: entry["parent"],
            comment: entry["comment"],
            created: Snapshots.parse_multipass_created(entry["created"]),
            children: entry["children"] || []
          )
        end
      end

      def create_snapshot(vm_name, snapshot_name, comment: nil)
        NameValidator.validate_vm_name!(vm_name)
        NameValidator.validate_vm_name!(snapshot_name)
        args = %W[snapshot --name #{snapshot_name}]
        args += %W[--comment #{comment}] if comment && !comment.empty?
        args << vm_name
        run(*args)
      end

      def restore_snapshot(vm_name, snapshot_name)
        NameValidator.validate_vm_name!(vm_name)
        NameValidator.validate_vm_name!(snapshot_name)
        run("restore", "--destructive", "#{vm_name}.#{snapshot_name}")
      end

      def delete_snapshot(vm_name, snapshot_name)
        NameValidator.validate_vm_name!(vm_name)
        NameValidator.validate_vm_name!(snapshot_name)
        run("delete", "--purge", "#{vm_name}.#{snapshot_name}")
      end
    end
  end
end
