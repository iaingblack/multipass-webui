# frozen_string_literal: true

require "logger"

module Multipass
  module SpecHelpers
    module_function

    # Read a captured multipass output fixture. Fixtures are real captures
    # committed to the repo — see spec/fixtures/multipass/README.md for
    # how to regenerate them with the canonical multipass <cmd> --format
    # json > path command. Using real catches catches output drift.
    def load_fixture(name)
      File.read(File.join(fixture_root, name))
    end

    def fixture_root
      @fixture_root ||= File.expand_path("../fixtures/multipass", __dir__)
    end

    # Build a logger that writes to /dev/null. Most specs don't assert on
    # log output but Client#initialize requires a logger.
    def discard_logger
      Logger.new(IO::NULL)
    end

    # Build a runner that records every call and replies from a hash
    # keyed by the joined argv. Calls that miss the table fail the test —
    # this forces each test to declare exactly what multipass invocations
    # it expects, catching silent arg changes.
    #
    # Returns a tuple [ runner_proc, calls_array ] so tests can assert on
    # the captured argv.
    def fake_runner(cases = {})
      calls = []
      runner = lambda { |args|
        calls << args
        key = args.join(" ")
        if cases.key?(key)
          [ cases[key], "", FakeStatus.success ]
        else
          raise "unexpected multipass call: #{args.inspect}"
        end
      }
      [ runner, calls ]
    end

    # Runner that always fails with the given error message. Useful for
    # testing error paths.
    def err_runner(message, exit_code = 1)
      calls = []
      runner = lambda { |args|
        calls << args
        [ "", message, FakeStatus.failure(exit_code) ]
      }
      [ runner, calls ]
    end

    # Runner that always raises — used to assert validation short-circuits
    # before any subprocess spawn.
    def no_call_runner
      lambda { |args|
        raise "runner should not have been called, but was with: #{args.inspect}"
      }
    end

    # Fake Process::Status so tests don't need to spawn real processes.
    class FakeStatus
      def self.success = new(0)
      def self.failure(code = 1) = new(code)

      def initialize(code)
        @code = code
      end

      def success? = @code.zero?
      def exitstatus = @code
    end
  end
end

RSpec.configure do |config|
  config.include Multipass::SpecHelpers, type: :service
end
