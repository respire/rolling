# frozen_string_literal: true

module Rolling
  class IOListener
    attr_reader :evloop

    def initialize(evloop, io, on_accept, on_eof)
      @evloop = evloop
      @io = io
      @on_accept = on_accept
      @on_eof = on_eof
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
      watcher = @evloop.watch(sock, &@on_eof)
      close_remote_connection = ->(ex) { watcher.unwatch_and_close(ex) }
      Util.safe_execute(close_remote_connection) { @on_accept.call(watcher) }
    end
  end
end
