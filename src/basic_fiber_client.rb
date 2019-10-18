module Rolling
  class BasicFiberClient
    def initialize(evloop, host:, port:)
      @evloop = evloop
      @host = host
      @port = port
      register_client
    end

    protected

    def on_connected(conn)
      raise NotImplementedError
    end

    def on_disconnected(ex, conn)
      raise NotImplementedError
    end

    def on_connection_failed(ex)
      raise NotImplementedError
    end

    def log_info(*args)
      Util.log_info(*args)
    end

    def log_exception(ex)
      Util.log_exception(ex)
    end

    private

    def internal_on_completed(res)
      case res.state
      when :ok
        # connection established
        @worker = FiberWorker.new
        @connection = Connection.new(@evloop, res.data, @worker)
        connected_handler = build_connected_handler
        state, data = @worker.post(connected_handler, @connection)
        raise data if state == :error
      when :error
        on_connection_failed(res.data)
      when :eof
        on_disconnected(res.data, @connection)
      end
    end

    def build_connected_handler
      proc do |conn|
        begin
          on_connected(conn)
        ensure
          conn.close
        end
      end
    end

    def register_client
      socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      addr = Socket.sockaddr_in(@port, @host)
      @evloop.connect(socket, addr, &method(:internal_on_completed))
    end
  end
end
