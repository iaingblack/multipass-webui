# frozen_string_literal: true

require "pathname"
require "fileutils"

module Multipass
  module Cloudinit
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module_function

    # Validate that content is valid cloud-init YAML.
    # Returns nil if valid; raises +ArgumentError+ with a useful message
    # otherwise. Mirrors the Go client's two checks:
    #   1. Must start with "#cloud-config"
    #   2. Must parse as YAML
    def validate_cloud_init_yaml!(content)
      trimmed = content.to_s.strip
      raise ArgumentError, "content is empty" if trimmed.empty?

      first_line = trimmed.split("\n", 2).first.strip
      unless first_line == "#cloud-config"
        raise ArgumentError, "first line must be '#cloud-config'"
      end

      require "yaml"
      YAML.safe_load(content, aliases: true) # raises on invalid YAML
      nil
    end

    # Filename + path safety for cloud-init template CRUD.
    # Returns the safe absolute path within +base_dir+, or raises
    # +ArgumentError+ if the name is dangerous.
    def sanitize_template_name!(base_dir, name)
      raise ArgumentError, "template name is required" if name.nil? || name.empty?
      if name.include?("/") || name.include?("\\") || name.include?("..")
        raise ArgumentError, "invalid template name"
      end
      unless name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\.(ya?ml)\z/i)
        raise ArgumentError, "template name must end in .yml or .yaml and use only safe characters"
      end

      abs_base = File.expand_path(base_dir)
      abs_path = File.expand_path(File.join(abs_base, name))
      rel = Pathname.new(abs_path).relative_path_from(Pathname.new(abs_base))
      if rel.to_s.start_with?("..")
        raise ArgumentError, "invalid template name"
      end
      abs_path
    end

    module InstanceMethods
      # Find cloud-config YAML files in +search_dirs+. Returns
      # +TemplateOption+s for files whose first non-blank line is exactly
      # +"#cloud-config"+.
      def scan_cloud_init_templates(search_dirs)
        seen = {}
        options = []

        search_dirs.each do |dir|
          entries =
            begin
              Dir.entries(dir)
            rescue SystemCallError
              next # unreadable directory — skip silently
            end

          entries.each do |entry|
            next if entry == "." || entry == ".."
            path = File.join(dir, entry)
            next if File.directory?(path)
            next unless entry.downcase.end_with?(".yml", ".yaml")

            abs_path = File.expand_path(path)
            next if seen.key?(abs_path)
            next unless cloud_config_header?(abs_path)

            seen[abs_path] = true
            options << Types::TemplateOption.new(label: entry, path: abs_path)
          end
        end
        options
      end

      def read_cloud_init_template(base_dir, name)
        path = Cloudinit.sanitize_template_name!(base_dir, name)
        File.read(path)
      rescue Errno::ENOENT
        raise ArgumentError, "template not found"
      end

      def write_cloud_init_template(base_dir, name, content)
        path = Cloudinit.sanitize_template_name!(base_dir, name)
        FileUtils.mkdir_p(base_dir)
        File.write(path, content)
      end

      def delete_cloud_init_template(base_dir, name)
        path = Cloudinit.sanitize_template_name!(base_dir, name)
        raise ArgumentError, "template not found" unless File.exist?(path)
        File.delete(path)
      end

      private

      def cloud_config_header?(path)
        File.open(path) do |f|
          line = f.gets
          return false if line.nil?
          line.strip == "#cloud-config"
        end
      rescue SystemCallError
        false
      end
    end
  end
end
