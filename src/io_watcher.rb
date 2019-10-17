# frozen_string_literal: true

module Rolling
  class IOWatcher
    AsyncReadRequest = Struct.new(:nbytes, :callback)
    AsyncReadResult = Struct.new(:state, :data)
    AsyncWriteRequest = Struct.new(:buffer, :callback)
    AsyncWriteResult = Struct.new(:state, :data)
    attr_reader :evloop, :remote_addr, :remote_port

    def initialize(evloop, io)
      @evloop = evloop
      @io = io
      @local_addr = io.local_address
      @remote_addr = io.remote_address
      @monitor = selector.register(io, :rw)
      @monitor.interests = nil
      @monitor.value = method(:handle_io_events)
      @monitoring_read = false
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

    def async_read(nbytes, &callback)
      read_data_from_chunks(nbytes, callback)
    end

    def async_read_some(&callback)
      read_data_from_chunks(-1, callback)
    end

    def async_write(data, &callback)
      data = data.join if data.is_a?(::Array)
      raise ::ArgumentError, 'data to write should be a non-empty string' if !data.is_a?(::String) || data.empty?

      @wseqs << AsyncWriteRequest.new(@write_chunks.add(data), callback)
      check_if_any_wseq_can_be_resolved
      self
    end

    def unwatch_and_close(ex = nil)
      @eof = true
      @eof_reason = ex
      unwatch.close
      @io
    end

    def unwatch
      selector.deregister(@io)
      @io
    end

    private

    def selector
      @evloop.instance_variable_get(:@selector)
    end

    def handle_io_events(monitor)
      if monitor.readable?
        bytes_read = nil
        Util.safe_execute(default_errback) { bytes_read = @read_chunks.read_some(monitor.io) }
        default_errback.call if !@read_chunks.backoff? && bytes_read&.zero?
        check_if_any_rseq_can_be_resolved
        if (@rseqs.empty? || @read_chunks.backoff?) && !monitor.closed?
          @monitoring_read = false
          monitor.remove_interest(:r)
        end
      elsif monitor.writable?
        bytes_sent = nil
        Util.safe_execute(method(:unwatch_and_close)) { bytes_sent = @write_chunks.write_some(monitor.io) }
        check_if_any_wseq_can_be_resolved
      end
    end

    def default_errback
      @default_errback ||= method(:unwatch_and_close)
    end

    def read_data_from_chunks(nbytes, callback)
      if @eof
        res = AsyncReadResult.new(:eof, @eof_reason)
        Util.safe_execute(default_errback) { callback.call(res) }
      else
        data = nbytes < 0 ? @read_chunks.pull : @read_chunks.get(nbytes)
        if data == :unavailable
          @rseqs << AsyncReadRequest.new(nbytes, callback)
        else
          res = AsyncReadResult.new(:ok, data)
          Util.safe_execute(default_errback) { callback.call(res) }
        end
      end

      if !@read_chunks.backoff? && !@rseqs.empty? && !@monitoring_read
        @monitoring_read = true
        @monitor.add_interest(:r)
      end

      self
    end

    def check_if_any_rseq_can_be_resolved
      return if @rseqs.empty?

      purge_idx = -1
      @rseqs.each do |rseq|
        res = nil
        state = :ok

        if @eof
          state = :eof
          res = @eof_reason
        else
          res = rseq.nbytes == -1 ? @read_chunks.pull : @read_chunks.get(rseq.nbytes)
          break if res == :unavailable
        end

        ret = AsyncReadResult.new(state, res)
        errback = @eof ? nil : default_errback
        Util.safe_execute(errback) { rseq.callback.call(ret) }

        purge_idx += 1
      end

      @rseqs.slice!(0..purge_idx) if purge_idx >= 0
    end

    def check_if_any_wseq_can_be_resolved
      return if @wseqs.empty?

      purge_idx = -1
      @wseqs.each do |wseq|
        state = :ok
        res = wseq.buffer

        if @eof
          state = :eof
          res = @eof_reason
        elsif wseq.buffer.remaining > 0
          break
        end

        ret = AsyncWriteResult.new(state, res)
        errback = method(:unwatch_and_close)

        @evloop.next_tick do
          Util.safe_execute(errback) { wseq.callback.call(ret) }
        end

        purge_idx += 1
      end

      @wseqs.slice!(0..purge_idx) if purge_idx >= 0

      return if @eof

      if @wseqs.empty?
        @monitor.remove_interest(:w)
      else
        @monitor.add_interest(:w)
      end
    end
  end
end
