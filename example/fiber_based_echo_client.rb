# frozen_string_literal: true

require_relative '../src/rolling'
require 'securerandom'

class Client < Rolling::BasicFiberClient
  def initialize(evloop)
    super(evloop, host: '127.0.0.1', port: 8088)

    @nbytes_read = 0
    @nbytes_sent = 0
    @rx = 0
    @tx = 0
    @flip = false
    @mb_to_send = 16
    @bytes_to_send = @mb_to_send * 1024 * 1024
    @content = String.new('', capacity: @bytes_to_send)
    @mb_to_send.times.each do
      @content << SecureRandom.random_bytes(1024 * 1024)
    end
  end

  def on_connected(conn)
    log_info "connection established. #{conn}"

    loop do
      res = conn.write(@content)
      log_info "#{res}"
      break unless res.state == :ok

      @nbytes_sent += res.data
      @tx_last_ticks ||= Rolling::Task.current_ticks
      current_ticks = Rolling::Task.current_ticks
      if current_ticks - @tx_last_ticks >= 3
        @tx_last_nbytes_read ||= 0
        current_nbytes_read = @nbytes_sent
        @tx = ((current_nbytes_read - @tx_last_nbytes_read) / 1024.0 / (current_ticks - @tx_last_ticks)).round
        @tx_last_nbytes_read = current_nbytes_read
        @tx_last_ticks = current_ticks
        @flip = true
      end

      log_info '1'
      res = conn.read(@content.bytesize)
      log_info '2'
      break unless res.state == :ok
      @nbytes_read += res.data.bytesize
      @rx_last_ticks ||= Rolling::Task.current_ticks
      current_ticks = Rolling::Task.current_ticks
      if current_ticks - @rx_last_ticks >= 3
        @rx_last_nbytes_read ||= 0
        current_nbytes_read = @nbytes_read
        @rx = ((current_nbytes_read - @rx_last_nbytes_read) / 1024.0 / (current_ticks - @rx_last_ticks)).round
        @rx_last_nbytes_read = current_nbytes_read
        @rx_last_ticks = current_ticks
        @flip = true
      end

      if @flip
        Rolling::Util.log_info "RX: #{@rx} KB/s | TX: #{@tx} KB/s"
        @flip = false
      end
    end
  end

  def on_disconnected(_, conn)
    log_info "disconnected from #{conn}"
  end

  def on_connection_failed(_)
    log_info 'cannot connect to server'
  end
end

evloop = Rolling::EventLoop.new
Client.new(evloop)
evloop.run
