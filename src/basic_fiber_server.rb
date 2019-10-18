# frozen_string_literal: true

module Rolling
  class BasicFiberServer
    def initialize(evloop, host:, port:)
      @evloop = evloop
      @host = host
      @port = port
      @hnds = {}
      @accept_handler = build_accept_handler
      register_server
    end

    protected

    def on_accept(_conn)
      raise NotImplementedError
    end

    def on_disconnected(_ex, _conn)
      raise NotImplementedError
    end

    def log_info(*args)
      Util.log_info(*args)
    end

    def log_exception(ex)
      Util.log_exception(ex)
    end

    private

    def internal_on_accept(watcher)
      worker = FiberWorker.new
      conn = Connection.new(@evloop, watcher, worker)
      @hnds[watcher] = {
        conn: conn,
        worker: worker
      }
      state, data = worker.post(@accept_handler, conn)
      raise data if state == :error
    end

    def internal_on_disconnected(ex, watcher)
      hnd = @hnds.delete watcher
      on_disconnected(ex, hnd[:conn])
    end

    def build_accept_handler
      proc do |conn|
        on_accept(conn)
      ensure
        conn.close
      end
    end

    def register_server
      server = TCPServer.new @host, @port
      @evloop.listen(server, method(:internal_on_accept), method(:internal_on_disconnected))
    end
  end
end
