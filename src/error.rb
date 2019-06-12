# frozen_string_literal: true

module Rolling
  class Error < ::StandardError
  end

  class ReadBufferChunksOverflowError < Error
  end

  class WriteBufferChunksOverflowError < Error
  end
end
