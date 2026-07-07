# frozen_string_literal: true

require "open3"
require "securerandom"
require "stringio"

module Multipass
  # Client wraps the +multipass+ CLI binary.
  #
  # == Command execution
  # All subprocess interaction goes through +#run+ (or +#run_streaming+).
  # Tests inject a fake runner via the +runner:+ constructor argument so no
  # real subprocess is spawned — the test fixtures in
  # +spec/fixtures/multipass/+ are real captures, used to catch output drift.
  #
  # == Name validation (flag-injection defense)
  # Every method that passes a name to +exec+ calls
  # +Multipass::NameValidator.validate_vm_name!+ *before* spawning. The HTTP
  # boundary (controller) does the same check first to return clean 400s.
  # The two layers exist so internal callers (jobs, the LLM agent) that
  # bypass the controller still get the guard.
  class Client
    # All operations are mixed in as modules to keep this file focused on
    # the runner; see vms.rb, snapshots.rb, mounts.rb, networks.rb,
    # images.rb, transfers.rb, cloudinit.rb, playbooks.rb.
    include Vms
    include Snapshots
    include Mounts
    include Networks
    include Images
    include Transfers
    include Cloudinit
    include Playbooks

    attr_reader :logger, :runner

    # Construct a Client that calls the real +multipass+ binary.
    # In test mode, pass +runner:+ to inject a fake (see Client.with_runner).
    def initialize(logger: Rails.logger, runner: nil)
      @logger = logger
      @runner = runner || method(:default_runner)
    end

    # Convenience constructor for tests: takes a Proc that receives an args
    # array and returns [stdout, stderr, status].
    def self.with_runner(runner, logger: Logger.new(IO::NULL))
      new(logger:, runner:)
    end

    # Execute +multipass+ with +args+ and return trimmed stdout as a string.
    # On non-zero exit, raises +Multipass::Client::CommandError+ carrying
    # both stdout (often empty) and stderr (the actual error message).
    def run(*args)
      stdout, stderr, status = runner.call(args)
      return stdout.strip if status.success?

      log_failure(args, status, stderr)
      raise CommandError.new(args, status, stdout, stderr)
    end

    # Execute +multipass+ with +args+ streaming stdout line-by-line to the
    # supplied block. Returns the full combined output. Used by Ansible
    # playbook runs and any long-running command where we want live output.
    #
    # The block is optional; without one this behaves like +#run+.
    def run_streaming(*args)
      stdout_io = StringIO.new
      Open3.popen3("multipass", *args) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stdout.each_line do |line|
          stdout_io.puts(line)
          yield(line.chomp) if block_given?
        end
        err = stderr.read
        status = wait_thr.value
        unless status.success?
          log_failure(args, status, err)
          raise CommandError.new(args, status, stdout_io.string, err)
        end
      end
      stdout_io.string.strip
    end

    # Generate a random VM name like "VM-a1b2".
    # Uses +SecureRandom+ for cryptographic randomness — same charset and
    # length as the upstream Go implementation (4 chars from [a-z0-9]).
    def self.random_vm_name
      charset = ("a".."z").to_a + ("0".."9").to_a
      suffix = (0...Constants::VM_NAME_RANDOM_LENGTH).map do
        charset[SecureRandom.random_number(charset.length)]
      end.join
      Constants::VM_NAME_PREFIX + suffix
    end

    # Error class for non-zero multipass exit. Carries stderr separately so
    # callers can surface a useful message without re-running the command.
    class CommandError < StandardError
      attr_reader :args, :status, :stdout, :stderr

      def initialize(args, status, stdout, stderr)
        @args = args
        @status = status
        @stdout = stdout
        @stderr = stderr.to_s.strip
        cmd = args.join(" ")
        super("multipass #{cmd} failed (exit #{status.exitstatus}): #{@stderr}")
      end
    end

    private

    # The default runner uses Open3.capture3 to invoke +multipass+ and return
    # [stdout, stderr, status]. This is the only place that actually spawns
    # the subprocess; everything else delegates through +#run+.
    def default_runner(args)
      cmd = [ "multipass", *args ]
      logger.debug { "[multipass] exec: #{cmd.join(' ')}" }
      Open3.capture3(*cmd)
    rescue SystemCallError => e
      # E.g. ENOENT when multipass binary isn't on PATH
      [ "", "multipass not installed or not on PATH: #{e.message}", FakeStatus.failure ]
    end

    def log_failure(args, status, stderr)
      logger.error("[multipass] exec failed: multipass #{args.join(' ')} " \
                   "(exit #{status.exitstatus}): #{stderr.to_s.strip}")
    end

    # A duck-typed Process::Status for synthetic failure paths (e.g. ENOENT).
    class FakeStatus
      def self.failure
        new
      end

      def success?
        false
      end

      def exitstatus
        127
      end
    end

    private_constant :FakeStatus
  end
end
