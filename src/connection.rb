# frozen_string_literal: true

module Rolling
  class Connection
    def initialize(evloop, watcher, worker)
      @evloop = evloop
      @watcher = watcher
      @worker = worker
    end

    def inspect
      @watcher.inspect
    end

    def to_s
      inspect
    end

    def read(nbytes)
      @watcher.fiber_worker_read(nbytes, @worker)
    end

    def read_some
      @watcher.fiber_worker_read_some(@worker)
    end

    def write(data)
      @watcher.fiber_worker_write(data, @worker)
    end

    def close
      @watcher.unwatch_and_close
    end
  end
end
