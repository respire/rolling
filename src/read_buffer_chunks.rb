# frozen_string_literal: true

module Rolling
  class ReadBufferChunks
    def initialize
      @chunks = []
      @nbytes_per_chunks = 16_384
      @max_chunks = 64
      @total_nbytes = 0
    end

    def can_read?(nbytes)
      @total_nbytes >= nbytes
    end

    def get(nbytes)
      return '' if nbytes < 1
      return :unavailable unless can_read?(nbytes)

      bytes_to_read = nbytes
      strs_read = []
      purge_idx = -1
      @chunks.each do |chunk|
        chunk.flip
        bytes_can_read = chunk.limit > bytes_to_read ? bytes_to_read : chunk.limit
        bytes_to_read -= bytes_can_read
        strs_read << chunk.get(bytes_can_read)
        if chunk.remaining.zero?
          purge_idx += 1
        else
          chunk.compact
        end
        break if bytes_to_read < 1
      end

      @chunks.slice!(0..purge_idx) if purge_idx >= 0

      @total_nbytes -= nbytes
      strs_read.join
    end

    def read_some(io)
      total_bytes_read = 0
      loop do
        chunk = find_an_available_chunk_to_fill
        nbytes = chunk.read_from(io)
        total_bytes_read += nbytes
        break if nbytes.zero?
      end
      @total_nbytes += total_bytes_read
      total_bytes_read
    end

    private

    def find_an_available_chunk_to_fill
      last_chunk = @chunks.last
      last_chunk = append_chunks if last_chunk.nil? || last_chunk.full?
      last_chunk
    end

    def append_chunks
      # TODO: allow different overflow handling policies. e.g. backoff
      raise ReadBufferChunksOverflowError, "nbytes_per_chunks: #{@nbytes_per_chunks}, max_chunks: #{@max_chunks}" if @chunks.length >= @max_chunks

      chunk = NIO::ByteBuffer.new(@nbytes_per_chunks)
      @chunks << chunk
      chunk
    end
  end
end
