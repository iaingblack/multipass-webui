# frozen_string_literal: true

module Multipass
  module SshKey
    module_function

    # Returns the path to the multipass SSH private key if it exists,
    # or +nil+ if not found. Used to populate Ansible inventory files.
    def find_multipass_ssh_key
      candidates.find { |path| File.exist?(path) }
    end

    def candidates
      case RbConfig::CONFIG["host_os"]
      when /darwin/
        [ "/var/root/Library/Application Support/multipassd/ssh-keys/id_rsa" ]
      when /linux/
        [
          "/var/snap/multipass/common/data/multipassd/ssh-keys/id_rsa",
          "/var/lib/multipass/ssh-keys/id_rsa"
        ]
      when /mswin|mingw|windows/
        program_data = ENV.fetch("ProgramData", "C:\\ProgramData")
        [ File.join(program_data, "Multipass", "data", "ssh-keys", "id_rsa") ]
      else
        []
      end
    end
  end
end
