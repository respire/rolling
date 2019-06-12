# frozen_string_literal: true

module Rolling
  class IOConnector
    AsyncConnectResult = Struct.new(:state, :data)
    attr_reader :evloop

    def initialize(evloop, io, remote_addr, &callback)
      @evloop = evloop
      @io = io
      @remote_addr = remote_addr
      @callback = callback
      @monitor = selector.register(io, :w)
      @monitor.interests = nil
      @monitor.value = method(:handle_io_events)
      @evloop.next_tick(&method(:try_to_connect))
    end

    private

    def selector
      @evloop.instance_variable_get(:@selector)
    end

    def detach
      selector.deregister(@io)
      @io
    end

    def try_to_connect
      @io.connect_nonblock @remote_addr
      on_connection_established
    rescue Errno::EINPROGRESS
      @monitor.add_interest :w
    rescue ::StandardError => e
      on_connection_failed_with_exception(e)
    end

    def on_connection_failed_with_exception(e)
      Util.log_exception(e)
      detach
      ret = AsyncConnectResult.new(:error, e)
      Util.safe_execute { @callback.call(ret) }
    end

    def on_connection_established
      watcher = @evloop.watch(detach)
      close_remote_connection = ->(ex) { watcher.unwatch_and_close(ex) }
      ret = AsyncConnectResult.new(:ok, watcher)
      Util.safe_execute(close_remote_connection) { @callback.call(ret) }
    end

    def handle_io_events(monitor)
      return unless monitor.writable?

      @io.connect_nonblock @remote_addr
    rescue ::Errno::EISCONN
      on_connection_established
    rescue ::StandardError => e
      on_connection_failed_with_exception(e)
    end
  end
end
