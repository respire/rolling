# frozen_string_literal: true

require_relative '../src/rolling'

require 'socket'
require 'securerandom'

class TCPEchoClient
  def initialize(evloop)
    @evloop = evloop
    @nbytes_read = 0
    @nbytes_sent = 0
    @rx = 0
    @tx = 0
    register_client
  end

  private

  def on_completed(res)
    Rolling::Util.log_info res
    case res.state
    when :ok
      @watcher = res.data
      write_some
      read_some
    when :error
      Rolling::Util.log_info 'failed to connect to remote server'
      @evloop.stop
    end
  end

  def write_some
    content = 100.times.map { SecureRandom.hex }.join
    @watcher.async_write(content, &method(:on_write_complete))
  end

  def read_some
    @watcher.async_read_some(&method(:on_read_complete))
  end

  def on_write_complete(ret)
    # Rolling::Util.log_info ret
    case ret.state
    when :ok
      @nbytes_sent += ret.data
      @tx_last_ticks ||= Rolling::Task.current_ticks
      current_ticks = Rolling::Task.current_ticks
      if current_ticks - @tx_last_ticks >= 3
        @tx_last_nbytes_read ||= 0
        current_nbytes_read = @nbytes_read
        @tx = ((current_nbytes_read - @tx_last_nbytes_read) / 1024.0 / (current_ticks - @tx_last_ticks)).round
        Rolling::Util.log_info "RX: #{@rx} KB/s | TX: #{@tx} KB/s"
        @tx_last_nbytes_read = current_nbytes_read
        @tx_last_ticks = current_ticks
      end
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
      @nbytes_read += ret.data.bytesize
      @rx_last_ticks ||= Rolling::Task.current_ticks
      current_ticks = Rolling::Task.current_ticks
      if current_ticks - @rx_last_ticks >= 3
        @rx_last_nbytes_read ||= 0
        current_nbytes_read = @nbytes_read
        @rx = ((current_nbytes_read - @rx_last_nbytes_read) / 1024.0 / (current_ticks - @rx_last_ticks)).round
        Rolling::Util.log_info "RX: #{@rx} KB/s | TX: #{@tx} KB/s"
        @rx_last_nbytes_read = current_nbytes_read
        @rx_last_ticks = current_ticks
      end
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
