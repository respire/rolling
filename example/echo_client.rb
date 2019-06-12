# frozen_string_literal: true

require_relative '../src/rolling'

require 'socket'
require 'securerandom'

class TCPEchoClient
  def initialize(evloop)
    @evloop = evloop
    register_client
  end

  private

  def on_completed(res)
    Rolling::Util.log_info res
    case res.state
    when :ok
      @watcher = res.data
      @nbytes_read = 0
      write_some
      read_some
    when :error
      Rolling::Util.log_info 'failed to connect to remote server'
      @evloop.stop
    end
  end

  def write_some
    content = SecureRandom.hex
    @watcher.async_write(content, &method(:on_write_complete))
  end

  def read_some
    @watcher.async_read(32, &method(:on_read_complete))
  end

  def on_write_complete(ret)
    # Rolling::Util.log_info ret
    case ret.state
    when :ok
      write_some
    when :eof
      Rolling::Util.log_info 'remote closed connection'
      @evloop.stop
    end
  end

  def on_read_complete(ret)
    # Rolling::Util.log_info ret
    case ret.state
    when :ok
      @nbytes_read += 32
      Rolling::Util.log_info "#{@nbytes_read} bytes read" if ((@nbytes_read / 32) % 100) == 0
      read_some
    when :eof
      Rolling::Util.log_info 'remote closed connection'
      @evloop.stop
    end
  end

  def register_client
    socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    addr = Socket.sockaddr_in(8088, '127.0.0.1')
    @evloop.connect(socket, addr, &method(:on_completed))
  end
end

evloop = Rolling::EventLoop.new
TCPEchoClient.new(evloop)
evloop.run
