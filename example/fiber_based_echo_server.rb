# frozen_string_literal: true

require_relative '../src/rolling'

class Server < Rolling::BasicFiberServer
  def on_accept(conn)
    log_info "connection established. #{conn}"
    total_bytes_sent = 0

    loop do
      res = conn.read_some
      break unless res.state == :ok

      res = conn.write(res.data)
      break unless res.state == :ok

      total_bytes_sent += res.data
    end

    log_info "#{total_bytes_sent} bytes written"
  end

  def on_disconnected(_, conn)
    log_info "disconnected from #{conn}"
  end
end

evloop = Rolling::EventLoop.new
Server.new(evloop, host: '127.0.0.1', port: 8088)
evloop.run
