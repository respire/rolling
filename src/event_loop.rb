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
        @task_manager.fire
        @selector.select(0.001, &method(:handle_events))
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

    def listen(io, &blk)
      IOListener.new(self, io, &blk)
    end

    def connect(io, remote_addr, &blk)
      IOConnector.new(self, io, remote_addr, &blk)
    end

    def watch(io)
      IOWatcher.new(self, io)
    end

    private

    def handle_events(monitor)
      monitor.value.call(monitor)
    end
  end
end
