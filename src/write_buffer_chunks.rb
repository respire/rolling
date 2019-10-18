# frozen_string_literal: true

module Rolling
  class WriteBufferChunks
    def initialize
      @chunks = []
      @nbytes_per_chunks = 16_384
    end

    def report
      {
        chunks: @chunks.length
      }
    end

    def add(data)
      total_bytes_to_send = data.bytesize
      data_chunks = []
      i = 0

      while total_bytes_to_send > 0
        chunk = NIO::ByteBuffer.new(@nbytes_per_chunks)
        j = i + @nbytes_per_chunks
        chunk << data.byteslice(i...j)
        chunk.flip
        data_chunks << chunk
        total_bytes_to_send -= chunk.limit
        i = j
      end

      @chunks += data_chunks

      data_chunks
    end

    def write_some(io)
      total_bytes_sent = 0
      purge_idx = -1

      @chunks.each do |chunk|
        nbytes = chunk.write_to(io)
        total_bytes_sent += nbytes
        break if nbytes.zero? || !chunk.remaining.zero?

        purge_idx += 1
      end
      @chunks.slice!(0..purge_idx) if purge_idx >= 0

      total_bytes_sent
    end
  end
end
