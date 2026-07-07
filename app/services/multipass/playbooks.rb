# frozen_string_literal: true

require "pathname"
require "fileutils"

module Multipass
  module Playbooks
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module_function

    # Filename + path safety for playbook CRUD. Same dual-defense as
    # +Cloudinit.sanitize_template_name!+ — regex + Pathname containment.
    def sanitize_playbook_name!(base_dir, name)
      raise ArgumentError, "playbook name is required" if name.nil? || name.empty?
      if name.include?("/") || name.include?("\\") || name.include?("..")
        raise ArgumentError, "invalid playbook name"
      end
      unless name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\.(ya?ml)\z/i)
        raise ArgumentError, "playbook name must end in .yml or .yaml and use only safe characters"
      end

      abs_base = File.expand_path(base_dir)
      abs_path = File.expand_path(File.join(abs_base, name))
      rel = Pathname.new(abs_path).relative_path_from(Pathname.new(abs_base))
      raise ArgumentError, "invalid playbook name" if rel.to_s.start_with?("..")
      abs_path
    end

    # Module-level CRUD — these don't need a Client instance because
    # playbooks are pure filesystem, no multipass CLI involved. Kept here
    # for parity with the Go API; callers can use either form.
    def list_playbooks(base_dir)
      entries =
        begin
          Dir.entries(base_dir)
        rescue Errno::ENOENT
          return []
        rescue SystemCallError
          raise
        end
      names = entries.reject { |e| e == "." || e == ".." }
                     .select { |e| !File.directory?(File.join(base_dir, e)) }
                     .select { |e| e.downcase.end_with?(".yml", ".yaml") }
      names.sort
    end

    def read_playbook(base_dir, name)
      path = sanitize_playbook_name!(base_dir, name)
      File.read(path)
    rescue Errno::ENOENT
      raise ArgumentError, "playbook not found"
    end

    def write_playbook(base_dir, name, content)
      path = sanitize_playbook_name!(base_dir, name)
      FileUtils.mkdir_p(base_dir)
      File.write(path, content)
    end

    def delete_playbook(base_dir, name)
      path = sanitize_playbook_name!(base_dir, name)
      raise ArgumentError, "playbook not found" unless File.exist?(path)
      File.delete(path)
    end

    module InstanceMethods
      # Delegate to module-level methods so callers using a Client instance
      # (e.g. from the LLM tool executor) get the same API.
      def list_playbooks(base_dir)    = Playbooks.list_playbooks(base_dir)
      def read_playbook(base_dir, n)  = Playbooks.read_playbook(base_dir, n)
      def write_playbook(base_dir, n, c) = Playbooks.write_playbook(base_dir, n, c)
      def delete_playbook(base_dir, n)   = Playbooks.delete_playbook(base_dir, n)
    end
  end
end
