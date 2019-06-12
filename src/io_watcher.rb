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
      @remote_port, @remote_addr = io.peeraddr[1..2]
      @monitor = selector.register(io, :rw)
      @monitor.interests = nil
      @monitor.value = method(:handle_io_events)
      @read_chunks = ReadBufferChunks.new
      @rseqs = []
      @write_chunks = WriteBufferChunks.new
      @wseqs = []
      @eof = false
      @eof_reason = nil
    end

    def inspect
      "\#<Rolling::IOWatcher:#{format('%#x', object_id)} #{@remote_addr}\##{@remote_port} #{@eof ? 'EOF' : ''} #{@eof_reason}>"
    end

    def async_read(nbytes, &callback)
      @rseqs << AsyncReadRequest.new(nbytes, callback)
      check_if_any_rseq_can_be_resolved
      nbytes
    end

    def async_write(data, &callback)
      data = data.join if data.is_a?(::Array)
      raise ::ArgumentError, 'data to write should be a non-empty string' if !data.is_a?(::String) || data.empty?

      @wseqs << AsyncWriteRequest.new(@write_chunks.add(data), callback)
      check_if_any_wseq_can_be_resolved

      data.length
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
        Util.safe_execute(method(:unwatch_and_close)) { bytes_read = @read_chunks.read_some(monitor.io) }
        unwatch_and_close if bytes_read&.zero?
        check_if_any_rseq_can_be_resolved
      elsif monitor.writable?
        bytes_sent = nil
        Util.safe_execute(method(:unwatch_and_close)) { bytes_sent = @write_chunks.write_some(monitor.io) }
        check_if_any_wseq_can_be_resolved
      end
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
          res = @read_chunks.get(rseq.nbytes)
          break if res == :unavailable
        end

        ret = AsyncReadResult.new(state, res)
        errback = method(:unwatch_and_close)

        @evloop.next_tick do
          Util.safe_execute(errback) { rseq.callback.call(ret) }
        end

        purge_idx += 1
      end

      @rseqs.slice!(0..purge_idx) if purge_idx >= 0

      return if @eof

      if @rseqs.empty?
        @monitor.remove_interest(:r)
      else
        @monitor.add_interest(:r)
      end
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
