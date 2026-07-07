# frozen_string_literal: true

require "open3"

module Multipass
  module Transfers
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      # Stream a file from the VM into the given IO. Used for downloads —
      # we pipe +multipass transfer vm:path -+ stdout directly into the
      # response body without buffering the whole file.
      def transfer_from_vm(vm_name, remote_path, io)
        NameValidator.validate_vm_name!(vm_name)
        src = "#{vm_name}:#{remote_path}"
        Open3.popen3("multipass", "transfer", src, "-") do |stdin, stdout, stderr, wait_thr|
          stdin.close
          IO.copy_stream(stdout, io)
          err = stderr.read
          status = wait_thr.value
          unless status.success?
            raise Client::CommandError.new(%W[transfer #{src} -], status,
                                           "", err.to_s.strip)
          end
        end
      end

      # Stream data from the given IO into a file in the VM. Used for uploads.
      def transfer_to_vm(vm_name, remote_path, io)
        NameValidator.validate_vm_name!(vm_name)
        dst = "#{vm_name}:#{remote_path}"
        Open3.popen3("multipass", "transfer", "-", dst) do |stdin, stdout, stderr, wait_thr|
          IO.copy_stream(io, stdin)
          stdin.close
          err = stderr.read
          status = wait_thr.value
          unless status.success?
            raise Client::CommandError.new(%W[transfer - #{dst}], status,
                                           "", err.to_s.strip)
          end
        end
      end
    end
  end
end
