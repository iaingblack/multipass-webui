# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multipass::Images, type: :service do
  let(:logger) { discard_logger }

  def build_client(runner)
    Multipass::Client.new(logger:, runner:)
  end

  describe "#find_images with real capture" do
    let(:fixture) { load_fixture("find.json") }

    it "parses images and blueprints, sorted images-first" do
      runner, = fake_runner("find --format json" => fixture)
      images = build_client(runner).find_images()

      # Real capture: 4 images + 7 blueprints (under "blueprints (deprecated)").
      img_count  = images.count { |i| i.type == "image" }
      bp_count   = images.count { |i| i.type == "blueprint" }
      expect(img_count).to eq(4)
      expect(bp_count).to eq(7)

      # Images come before blueprints after sort.
      expect(images.first.type).to eq("image")

      # Verify a specific image's aliases made it through.
      ubuntu = images.find { |i| i.name == "24.04" && i.type == "image" }
      expect(ubuntu).not_to be_nil
      expect(ubuntu.aliases.length).to eq(2)
      expect(ubuntu.release).to eq("24.04 LTS")

      # Sort within group: images alphabetical by name.
      image_names = images.select { |i| i.type == "image" }.map(&:name)
      expect(image_names).to eq(image_names.sort)
    end
  end
end
