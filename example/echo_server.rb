# frozen_string_literal: true

require_relative '../src/rolling'

require 'socket'

class Client
  attr_reader :watcher

  def initialize(watcher, on_disconnected)
    @watcher = watcher
    @on_disconnected = on_disconnected
    @nbytes_sent = 0
  end

  def inspect
    "\#<Client:#{format('%#x', object_id)} @watcher=#{@watcher.inspect}>"
  end

  def read_and_echo
    @watcher.async_read_some(&method(:echo_bytes))
    self
  end

  def echo_bytes(ret)
    # Rolling::Util.log_info ret
    case ret.state
    when :ok
      @watcher.async_write(ret.data, &method(:on_write_complete))
      read_and_echo
    when :eof
      @on_disconnected.call(self)
    end
  end

  def on_write_complete(ret)
    # Rolling::Util.log_info ret
    return unless ret.state == :ok

    @nbytes_sent += ret.data
    Rolling::Util.log_info "#{@nbytes_sent} bytes was echoed back" if (@nbytes_sent % 1024).zero?
  end
end

class TCPEchoServer
  def initialize(evloop)
    @evloop = evloop
    @listener = register_server
    @clients = []
  end

  private

  def accept(watcher)
    on_client_disconnected = method(:remove_client)
    client = Client.new(watcher, on_client_disconnected)
    @clients << client
    Rolling::Util.logger.info "connected to #{client.inspect}"
    Rolling::Util.logger.info "connected clients: #{@clients.length}"
    client.read_and_echo
  end

  def remove_client(client)
    @clients.delete client
    Rolling::Util.logger.info "disconnected from #{client.inspect}"
    Rolling::Util.logger.info "connected clients: #{@clients.length}"
  end

  def register_server
    server = TCPServer.new '127.0.0.1', 8088
    @evloop.listen(server, &method(:accept))
    @evloop.add_timer(3, &method(:report))
  end

  def report
    Rolling::Util.logger.info "connected clients: #{@clients.length}"
    @evloop.add_timer(3, &method(:report))
  end
end

evloop = Rolling::EventLoop.new
TCPEchoServer.new(evloop)
evloop.run
