# frozen_string_literal: true

module Rolling
  class ReadBufferChunks
    def initialize
      @chunks = []
      @nbytes_per_chunks = 16_384 # 16k
    end

    def backoff?
      @chunks.empty?
    end

    def pull(total_bytes_to_receive)
      total_bytes_to_receive = @nbytes_per_chunks if total_bytes_to_receive < 1
      nbytes = total_bytes_to_receive
      buffer_chunks = []

      while nbytes > 0
        chunk = NIO::ByteBuffer.new(@nbytes_per_chunks)
        chunk.limit = nbytes if nbytes < @nbytes_per_chunks
        buffer_chunks << chunk
        nbytes -= chunk.limit
      end

      @chunks += buffer_chunks

      [total_bytes_to_receive, buffer_chunks]
    end

    def read_some(io)
      purge_idx = -1
      bytes_received = 0

      @chunks.each do |chunk|
        bytes_received += chunk.read_from(io)
        break unless chunk.full?

        purge_idx += 1
      end

      @chunks.slice!(0..purge_idx) if purge_idx >= 0

      bytes_received
    end
  end
end
