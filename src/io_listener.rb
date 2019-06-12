# frozen_string_literal: true

module Rolling
  class IOListener
    attr_reader :evloop

    def initialize(evloop, io, &acceptor)
      @evloop = evloop
      @io = io
      @acceptor = acceptor
      @monitor = selector.register(io, :r)
      @monitor.value = method(:handle_io_events)
    end

    def unlisten
      selector.deregister(@io)
      @io
    end

    private

    def selector
      @evloop.instance_variable_get(:@selector)
    end

    def handle_io_events(monitor)
      return unless monitor.readable?

      sock = monitor.io.accept_nonblock
      watcher = @evloop.watch(sock)
      close_remote_connection = ->(ex) { watcher.unwatch_and_close(ex) }
      Util.safe_execute(close_remote_connection) { @acceptor.call(watcher) }
    end
  end
end
