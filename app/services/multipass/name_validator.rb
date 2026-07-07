# frozen_string_literal: true

module Multipass
  # Name validation is the dual-layer flag-injection defense:
  #   1. The HTTP boundary (controller) calls +NameValidator.validate_vm_name!+
  #      to return a clean 400 to the client.
  #   2. Every +Multipass::Client+ method that passes a name to +exec+ calls
  #      +NameValidator.validate_vm_name!+ again before spawning.
  #
  # Both layers use the same regex; the second catches anything that slips
  # through the first, and also guards against internal callers that bypass
  # the controller layer (background jobs, the LLM agent loop).
  module NameValidator
    VM_NAME_PATTERN       = /\A[a-zA-Z0-9][a-zA-Z0-9-]{0,62}\z/
    GROUP_NAME_PATTERN    = /\A[a-zA-Z0-9][a-zA-Z0-9 _-]{0,62}\z/
    PROFILE_ID_PATTERN    = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}\z/
    PLAYBOOK_FILE_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}\.ya?ml\z/

    class ValidationError < StandardError; end

    module_function

    # Returns true if +name+ is a valid multipass VM (or snapshot) name.
    # Same regex as the multipass CLI itself: leading letter/digit, then up
    # to 62 more letters/digits/hyphens. Rejecting a leading "-" is the
    # critical part — it blocks flag injection when the name reaches argv.
    def valid_vm_name?(name)
      name.is_a?(String) && VM_NAME_PATTERN.match?(name)
    end

    def valid_group_name?(name)
      name.is_a?(String) && GROUP_NAME_PATTERN.match?(name)
    end

    def valid_profile_id?(id)
      id.is_a?(String) && PROFILE_ID_PATTERN.match?(id)
    end

    def valid_playbook_filename?(name)
      name.is_a?(String) && PLAYBOOK_FILE_PATTERN.match?(name)
    end

    # Raise +ValidationError+ if invalid. Use this from the client layer
    # to short-circuit before any subprocess spawn.
    def validate_vm_name!(name)
      return if valid_vm_name?(name)

      raise ValidationError,
            "invalid VM name #{name.inspect}: must start with letter/digit and " \
            "contain only letters, digits, and hyphens (max 63 chars)"
    end

    def validate_group_name!(name)
      raise ValidationError, "invalid group name #{name.inspect}" if name !~ GROUP_NAME_PATTERN
    end

    def validate_profile_id!(id)
      raise ValidationError, "invalid profile id #{id.inspect}" if id !~ PROFILE_ID_PATTERN
    end

    def validate_playbook_filename!(name)
      raise ValidationError, "invalid playbook filename #{name.inspect}" if name !~ PLAYBOOK_FILE_PATTERN
    end
  end
end
