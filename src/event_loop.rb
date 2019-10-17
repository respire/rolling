# frozen_string_literal: true

module Rolling
  class EventLoop
    def initialize
      @selector = NIO::Selector.new
      Util.log_info "evloop-backend: #{@selector.backend}"
      @task_manager = TaskManager.new
      @state = :stopped
    end

    def run
      @state = :running

      until @state == :stopping || @state == :stopped
        select_timeout = @task_manager.fire
        @selector.select(select_timeout, &method(:handle_events))
      end

      @state = :stopped
    end

    def stop
      # TODO: multithread-friendly state management should be introduced in future so as to support reactor-per-thread model.
      @state = :stopping
    end

    def next_tick(&blk)
      @task_manager.append(0, &blk)
      self
    end

    def add_timer(secs, &blk)
      @task_manager.append(secs, &blk)
      self
    end

    def listen(io, on_accept, on_eof)
      IOListener.new(self, io, on_accept, on_eof)
    end

    def connect(io, remote_addr, &blk)
      IOConnector.new(self, io, remote_addr, &blk)
    end

    def watch(io, &eofback)
      IOWatcher.new(self, io, eofback)
    end

    private

    def handle_events(monitor)
      monitor.value.call(monitor)
    end
  end
end
