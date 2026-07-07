# frozen_string_literal: true

require "pty"
require "io/console"

module Terminals
  # SPIKE implementation: owns one PTY per session, in the Puma process.
  # This won't scale (one thread per terminal forever) but proves the
  # ActionCable + PTY + binary transport story end-to-end before we
  # commit to a worker-process architecture.
  #
  # Production shape (post-spike): move PTY ownership into a dedicated
  # `bin/terminald` worker that streams I/O via Redis pub/sub.
  # The channel then becomes a thin proxy between the browser and Redis.
  class Session
    SESSIONS = {} # session_id => Session instance (process-global)
    SESSIONS_MUTEX = Mutex.new

    SCROLLBACK_CAP = 64 * 1024 # 64 KiB, mirrors Go pty_store.go:20
    RESIZE_PREFIX_BYTE = 0x01  # 5-byte resize message: 0x01 + cols + rows (BE uint16)

    attr_reader :session_id, :vm_name, :scrollback

    def self.open(vm_name:, session_id:)
      sess = new(vm_name:, session_id:)
      SESSIONS_MUTEX.synchronize { SESSIONS[session_id] = sess }
      sess.start
      sess
    end

    def self.find(session_id)
      SESSIONS_MUTEX.synchronize { SESSIONS[session_id] }
    end

    def self.kill(session_id)
      SESSIONS_MUTEX.synchronize { SESSIONS.delete(session_id)&.kill }
    end

    def initialize(vm_name:, session_id:)
      @vm_name = vm_name
      @session_id = session_id
      @scrollback = String.new(encoding: "ASCII-8BIT")
      @scrollback_mutex = Mutex.new
      @output_broadcast_name = "terminal:#{session_id}:output"
      @closed = false
    end

    # Spawn the PTY and start the reader thread.
    def start
      # Verify the VM name before spawning — same flag-injection guard
      # as the rest of the app, applied at the service layer too.
      Multipass::NameValidator.validate_vm_name!(@vm_name)

      env = { "TERM" => "xterm-256color" }
      @master, @slave = PTY.open
      # Set a reasonable default winsize — matches Go pty_store_unix.go:34.
      @slave.winsize = [ 40, 120 ]
      Rails.logger.info("[terminal] spawning multipass shell #{@vm_name} for session #{@session_id}")
      @pid = spawn("multipass", "shell", @vm_name, in: @slave, out: @slave, err: @slave, pgroup: true)
      @slave.close
      Rails.logger.info("[terminal] spawned pid=#{@pid}")

      # Reader thread: reads PTY output in 4KB chunks (matches Go's read size),
      # appends to scrollback (cap 64KB), and broadcasts to all ActionCable
      # subscribers via ActionCable.server.broadcast.
      require "io/wait"
      @reader_thread = Thread.new do
        chunk_count = 0
        begin
          until @closed
            begin
              chunk = @master.read_nonblock(4096)
            rescue IO::WaitReadable
              # No data yet — block up to 100ms waiting for input, then retry.
              # wait_readable returns true when readable, nil on timeout.
              @master.wait_readable(0.1)
              retry unless @closed
              break
            end

            if chunk.nil? # EOF → process exited
              Rails.logger.info("[terminal] EOF on master after #{chunk_count} chunks")
              broadcast_output("\r\n[multipass shell exited]\r\n".b)
              break
            end
            chunk_count += 1
            append_scrollback(chunk)
            broadcast_output(chunk)
          end
        rescue IOError => e
          # Master closed — process exited
          Rails.logger.info("[terminal] IOError on master after #{chunk_count} chunks: #{e.message}")
          broadcast_output("\r\n[terminal closed: #{e.message}]\r\n".b)
        rescue StandardError => e
          Rails.logger.error("[terminal] reader thread crashed: #{e.class}: #{e.message}")
          raise
        ensure
          @closed = true
        end
      end
    end

    # Write user input (or resize message) to the PTY.
    def write(data)
      return if @closed

      # Detect the 5-byte resize prefix and apply via winsize.
      # See Go pty_store.go resize protocol: 0x01 + cols(BE u16) + rows(BE u16).
      if data.encoding == Encoding::BINARY && data.bytesize >= 5 && data.bytes.first == RESIZE_PREFIX_BYTE
        cols = data.bytes[1] * 256 + data.bytes[2]
        rows = data.bytes[3] * 256 + data.bytes[4]
        begin
          @master.winsize = [ rows, cols ]
        rescue SystemCallError
          # PTY gone — ignore
        end
        return
      end

      # Plain terminal input — write as-is.
      @master.write(data)
    rescue SystemCallError, IOError
      # PTY closed under us — drop the input silently
    end

    def kill
      return if @closed
      @closed = true
      @reader_thread&.kill
      # Kill the process group (matches Go's killProcGroup pattern).
      Process.kill("TERM", -@pid) if @pid
    rescue SystemCallError
      # already gone
    ensure
      @master&.close
      @slave&.close unless @slave&.closed?
      SESSIONS_MUTEX.synchronize { SESSIONS.delete(@session_id) }
    end

    private

    # Append to the ring buffer with a hard 64KB cap. Matches Go's
    # ringBuffer.Write (pty_store.go:32-41) which wraps writes around a
    # fixed-size byte slice.
    def append_scrollback(chunk)
      @scrollback_mutex.synchronize do
        @scrollback << chunk
        if @scrollback.bytesize > SCROLLBACK_CAP
          # Drop the oldest bytes beyond the cap. This isn't a true ring
          # buffer — it allocates fresh on each trim — but the cap keeps
          # the worst case bounded at 64KB.
          @scrollback.replace(@scrollback.bytes[-SCROLLBACK_CAP..])
        end
      end
    end

    # ActionCable broadcasts must be JSON-serialisable. We base64-encode
    # binary chunks so they survive transit cleanly; the Stimulus controller
    # decodes them back to a Uint8Array for xterm.js.
    def broadcast_output(binary_chunk)
      encoded = Base64.strict_encode64(binary_chunk)
      ActionCable.server.broadcast(@output_broadcast_name, { type: "output", data: encoded })
    end
  end
end
