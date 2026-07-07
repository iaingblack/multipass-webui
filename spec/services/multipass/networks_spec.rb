# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multipass::Networks, type: :service do
  let(:logger) { discard_logger }

  def build_client(runner)
    Multipass::Client.new(logger:, runner:)
  end

  describe "#list_networks with real capture" do
    let(:fixture) { load_fixture("networks.json") }

    it "parses networks and preserves types" do
      runner, = fake_runner("networks --format json" => fixture)
      nets = build_client(runner).list_networks()
      expect(nets.length).to eq(4)
      # Verify the real capture's first entry came through intact.
      first = nets.first
      expect(first.name).to eq("en0")
      expect(first.type).to eq("wifi")
      expect(first.description).to eq("Wi-Fi")
      # Ethernet entries preserved.
      ethernet_count = nets.count { |n| n.type == "ethernet" }
      expect(ethernet_count).to eq(3)
    end
  end

  describe "#list_networks with malformed JSON" do
    it "raises" do
      runner = ->(_) { [ "not json", "", Multipass::SpecHelpers::FakeStatus.success ] }
      expect { build_client(runner).list_networks }.to raise_error(JSON::ParserError)
    end
  end
end
