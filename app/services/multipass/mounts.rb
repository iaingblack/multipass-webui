# frozen_string_literal: true

module Multipass
  module Mounts
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      def list_mounts(vm_name)
        get_vm_info(vm_name).mounts
      end

      def add_mount(vm_name, source, target)
        NameValidator.validate_vm_name!(vm_name)
        run("mount", source, "#{vm_name}:#{target}")
      end

      def remove_mount(vm_name, target)
        NameValidator.validate_vm_name!(vm_name)
        run("umount", "#{vm_name}:#{target}")
      end
    end
  end
end
