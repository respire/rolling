# frozen_string_literal: true

module Rolling
  class WriteBufferChunks
    def initialize
      @chunks = []
      @max_total_nbytes = 16_777_216
      @total_nbytes = 0
    end

    def add(data)
      chunk = NIO::ByteBuffer.new(data.length)
      chunk << data
      chunk.flip

      # TODO: allow different overflow handling policies. e.g. backoff
      next_total_nbytes = @total_nbytes + chunk.limit
      raise WriteBufferChunksOverflowError, "max_total_nbytes: #{@max_total_nbytes}" if next_total_nbytes > @max_total_nbytes

      @total_nbytes = next_total_nbytes

      @chunks << chunk
      chunk
    end

    def write_some(io)
      total_bytes_sent = 0
      @chunks.each do |chunk|
        next if chunk.remaining.zero?

        nbytes = chunk.write_to(io)
        total_bytes_sent += nbytes
        break if nbytes.zero? || !chunk.remaining.zero?
      end
      @total_nbytes -= total_bytes_sent
      total_bytes_sent
    end
  end
end
