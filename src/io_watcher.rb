# frozen_string_literal: true

module Rolling
  class IOWatcher
    AsyncReadRequest = Struct.new(:chunks, :bytes_to_read, :callback)
    AsyncReadResult = Struct.new(:state, :data)
    AsyncWriteRequest = Struct.new(:chunks, :bytes_sent, :callback)
    AsyncWriteResult = Struct.new(:state, :data)
    attr_reader :evloop, :remote_addr, :remote_port

    def initialize(evloop, io, eofback)
      @evloop = evloop
      @io = io
      @eofback = eofback
      @local_addr = io.local_address
      @remote_addr = io.remote_address
      @monitor = selector.register(io, :rw)
      @monitor.interests = nil
      @monitor.value = method(:handle_io_events)
      @monitoring_read = false
      @monitoring_write = false
      @read_chunks = ReadBufferChunks.new
      @rseqs = []
      @write_chunks = WriteBufferChunks.new
      @wseqs = []
      @eof = false
      @eof_reason = nil
    end

    def inspect
      "\#<Rolling::IOWatcher:#{format('%#x', object_id)} @remote_addr=#{@remote_addr.inspect} @local_addr=#{@local_addr.inspect} #{@eof ? 'EOF' : ''} #{@eof_reason}>"
    end

    def to_s
      inspect
    end

    def report
      {
        local_addr: @local_addr.inspect,
        remote_addr: @remote_addr.inspect,
        rseqs: @rseqs.length,
        wseqs: @wseqs.length,
        rchunks: @read_chunks.report,
        wchunks: @write_chunks.report,
        interests: @monitor.interests,
        eof: @eof,
        eof_reason: @eof_reason
      }
    end

    def async_read(nbytes, &callback)
      request_read(nbytes, :callback, callback)
    end

    def async_read_some(&callback)
      request_read(0, :callback, callback)
    end

    def async_write(data, &callback)
      request_write(data, :callback, callback)
    end

    def fiber_worker_read(nbytes, fiber_worker)
      request_read(nbytes, :fiber_worker, fiber_worker)
    end

    def fiber_worker_read_some(fiber_worker)
      request_read(0, :fiber_worker, fiber_worker)
    end

    def fiber_worker_write(data, fiber_worker)
      request_write(data, :fiber_worker, fiber_worker)
    end

    def unwatch_and_close(ex = nil)
      return if @eof

      @eof = true
      @eof_reason = ex
      unwatch.close
      Util.safe_execute { @eofback.call(@eof_reason, self) }
      @io
    end

    def unwatch
      return if @monitor.closed?

      @monitor.close
      @monitoring_read = false
      @monitoring_write = false
      @io
    end

    private

    def selector
      @evloop.instance_variable_get(:@selector)
    end

    def handle_io_events(monitor)
      handle_readable(monitor) if monitor.readable?
      handle_writable(monitor) if monitor.writable?
    end

    def handle_readable(monitor)
      bytes_read = nil
      Util.safe_execute(default_errback) { bytes_read = @read_chunks.read_some(monitor.io) }
      if !@read_chunks.backoff? && bytes_read&.zero?
        # EOF
        default_errback.call
      elsif @read_chunks.backoff? && !monitor.closed?
        monitor.remove_interest(:r)
        @monitoring_read = false
      end
      check_if_any_rseq_can_be_resolved
    end

    def handle_writable(monitor)
      bytes_sent = nil
      Util.safe_execute(default_errback) { bytes_sent = @write_chunks.write_some(monitor.io) }
      check_if_any_wseq_can_be_resolved
      return unless @wseqs.empty? && !monitor.closed?

      monitor.remove_interest(:w)
      @monitoring_write = false
    end

    def default_errback
      @default_errback ||= method(:unwatch_and_close)
    end

    def request_read(nbytes, type, target)
      res = nil

      if @eof
        res = AsyncReadResult.new(:eof, @eof_reason)
      else
        bytes_to_read, chunks = @read_chunks.pull(nbytes)
        hnd = case type
              when :callback
                target
              when :fiber_worker
                target.resume_callback
              end
        @rseqs << AsyncReadRequest.new(chunks, bytes_to_read, hnd)
        unless @monitoring_read
          @monitor.add_interest(:r)
          @monitoring_read = true
        end
      end

      case type
      when :callback
        Util.safe_execute { target.call(res) } if res
      when :fiber_worker
        res.nil? ? Fiber.yield : res
      end
    end

    def request_write(data, type, target)
      res = nil

      if @eof
        res = AsyncWriteResult.new(:eof, @eof_reason)
      else
        chunks = @write_chunks.add(data)
        hnd = case type
              when :callback
                target
              when :fiber_worker
                target.resume_callback
              end
        @wseqs << AsyncWriteRequest.new(chunks, data.bytesize, hnd)
        unless @monitoring_write
          @monitor.add_interest(:w)
          @monitoring_write = true
        end
      end

      case type
      when :callback
        Util.safe_execute { target.call(res) } if res
      when :fiber_worker
        res.nil? ? Fiber.yield : res
      end
    end

    def check_if_any_rseq_can_be_resolved
      purge_idx = -1

      @rseqs.each do |rseq|
        res = nil
        state = nil

        if @eof
          state = :eof
          res = @eof_reason
        elsif rseq.chunks.last.full?
          state = :ok
          # WARNING: MIGHT COPY TWICE
          res = String.new('', capacity: rseq.bytes_to_read)
          rseq.chunks.each do |chunk|
            res << chunk.flip.get
          end
        else
          break
        end

        ret = AsyncReadResult.new(state, res)
        errback = @eof ? nil : default_errback
        Util.safe_execute(errback) { rseq.callback.call(ret) }

        purge_idx += 1
      end

      @rseqs.slice!(0..purge_idx) if purge_idx >= 0
    end

    def check_if_any_wseq_can_be_resolved
      purge_idx = -1
      @wseqs.each do |wseq|
        if @eof
          res = AsyncWriteResult.new(:eof, @eof_reason)
          Util.safe_execute { wseq.callback.call(res) }
        else
          chunks_purge_idx = -1
          wseq.chunks.each do |chunk|
            break if chunk.remaining > 0

            chunks_purge_idx += 1
          end
          wseq.chunks.slice!(0..chunks_purge_idx) if chunks_purge_idx >= 0
          break unless wseq.chunks.empty?

          res = AsyncWriteResult.new(:ok, wseq.bytes_sent)
          Util.safe_execute(default_errback) { wseq.callback.call(res) }
        end

        purge_idx += 1
      end

      @wseqs.slice!(0..purge_idx) if purge_idx >= 0
    end
  end
end
