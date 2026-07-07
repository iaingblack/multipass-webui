# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multipass::Snapshots, type: :service do
  let(:logger) { discard_logger }

  def build_client(runner)
    Multipass::Client.new(logger:, runner:)
  end

  let(:snapshot_info_json) do
    <<~JSON
      {
        "errors": [],
        "info": {
          "vm-a": {
            "snapshots": {
              "snap1": {"parent": "", "comment": "first", "created": "Thu 16 Apr 20:52:16 2026 BST", "children": ["snap2"]},
              "snap2": {"parent": "snap1", "comment": "second", "created": "Thu 16 Apr 20:52:24 2026 BST", "children": []}
            }
          }
        }
      }
    JSON
  end

  describe "#list_snapshots parses rich fields" do
    it "captures parent, comment, created (UTC), children" do
      runner, = fake_runner("info vm-a --snapshots --format json" => snapshot_info_json)
      snaps = build_client(runner).list_snapshots("vm-a")
      expect(snaps.length).to eq(2)
      by_name = snaps.to_h { |s| [ s.name, s ] }

      snap1 = by_name.fetch("snap1")
      expect(snap1.comment).to eq("first")
      expect(snap1.instance).to eq("vm-a")
      # "Thu 16 Apr 20:52:16 2026 BST" → UTC = 19:52:16
      expect(snap1.created).to start_with("2026-04-16T19:52:16")
      expect(snap1.children).to eq(%w[snap2])

      expect(by_name.fetch("snap2").parent).to eq("snap1")
    end
  end

  describe "#list_snapshots with no snapshots" do
    it "returns an empty array" do
      runner, = fake_runner(
        "info vm-a --snapshots --format json" => '{"errors":[],"info":{"vm-a":{"snapshots":{}}}}'
      )
      snaps = build_client(runner).list_snapshots("vm-a")
      expect(snaps).to eq([])
    end
  end

  describe "#list_snapshots rejects invalid VM name" do
    it "raises before subprocess spawn" do
      expect { build_client(no_call_runner).list_snapshots("--all") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#list_snapshots with real capture" do
    let(:fixture) { load_fixture("info_snapshots.json") }

    it "parses parent chains, children, and UTC timestamps" do
      runner, = fake_runner("info ansible --snapshots --format json" => fixture)
      snaps = build_client(runner).list_snapshots("ansible")
      expect(snaps.length).to eq(4)
      by_name = snaps.to_h { |s| [ s.name, s ] }

      expect(by_name.fetch("test-1").parent).to eq("")
      expect(by_name.fetch("another-snaphot").parent).to eq("other-snapshot")
      expect(by_name.fetch("test-1").children.length).to eq(2)
      # BST = UTC+1, 20:53:27 BST → 19:53:27 UTC
      expect(by_name.fetch("extra-snapshot").created).to start_with("2026-04-16T19:53:27")

      newest = snaps.max_by(&:created)
      expect(newest.name).to eq("extra-snapshot")
    end
  end

  describe "#create_snapshot" do
    it "with comment" do
      runner, = fake_runner("snapshot --name snap1 --comment hello vm-a" => "ok")
      build_client(runner).create_snapshot("vm-a", "snap1", comment: "hello")
    end

    it "without comment omits the flag" do
      runner, = fake_runner("snapshot --name snap1 vm-a" => "ok")
      build_client(runner).create_snapshot("vm-a", "snap1", comment: "")
    end

    it "rejects invalid VM name" do
      expect { build_client(no_call_runner).create_snapshot("--all", "s", comment: "") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end

    it "rejects invalid snapshot name" do
      expect { build_client(no_call_runner).create_snapshot("vm", "--evil", comment: "") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#restore_snapshot" do
    it "builds the destructive restore argv" do
      runner, = fake_runner("restore --destructive vm-a.snap1" => "ok")
      build_client(runner).restore_snapshot("vm-a", "snap1")
    end

    it "rejects invalid snapshot name" do
      expect { build_client(no_call_runner).restore_snapshot("vm", "--evil") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe "#delete_snapshot" do
    it "builds the purge argv" do
      runner, = fake_runner("delete --purge vm-a.snap1" => "ok")
      build_client(runner).delete_snapshot("vm-a", "snap1")
    end
  end

  describe ".parse_multipass_created" do
    {
      ""                                       => "",
      "Thu Apr 16 20:52:16 2026 BST"           => "2026-04-16T19:52:16", # ANSIC, month-before-day
      "Thu 16 Apr 20:52:16 2026 BST"           => "2026-04-16T19:52:16", # day-before-month
      "2026-04-16T19:52:16Z"                   => "2026-04-16T19:52:16",
      "garbage string no one expects"          => "garbage string no one expects" # passthrough
    }.each do |input, expected_prefix|
      it "parses #{input.inspect} → starts with #{expected_prefix.inspect}" do
        actual = Multipass::Snapshots.parse_multipass_created(input)
        expect(actual).to start_with(expected_prefix)
      end
    end
  end
end
