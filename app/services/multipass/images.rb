# frozen_string_literal: true

require "json"

module Multipass
  module Images
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      # Returns available images and blueprints from +multipass find+.
      # Note the JSON response uses the deprecated key
      # +"blueprints (deprecated)"+ — we still surface those entries.
      def find_images
        output = run("find", "--format", "json")
        resp = JSON.parse(output)

        results = []
        resp.fetch("images", {}).each do |name, img|
          results << Types::ImageInfo.new(
            name:,
            aliases: img["aliases"] || [],
            os: img["os"],
            release: img["release"],
            remote: img["remote"],
            version: img["version"],
            type: "image"
          )
        end
        resp.fetch("blueprints (deprecated)", {}).each do |name, img|
          results << Types::ImageInfo.new(
            name:,
            aliases: img["aliases"] || [],
            os: img["os"],
            release: img["release"],
            remote: img["remote"],
            version: img["version"],
            type: "blueprint"
          )
        end

        # Sort: images first, then blueprints, alphabetical within each group
        results.sort_by! { |r| [ r.type == "image" ? 0 : 1, r.name ] }
      end
    end
  end
end
