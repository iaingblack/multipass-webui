# frozen_string_literal: true

require "json"

module Multipass
  module Networks
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      def list_networks
        output = run("networks", "--format", "json")
        resp = JSON.parse(output)
        resp.fetch("list", []).map do |net|
          Types::NetworkInfo.new(
            name: net["name"],
            type: net["type"],
            description: net["description"]
          )
        end
      end
    end
  end
end
