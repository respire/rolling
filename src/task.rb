# frozen_string_literal: true

module Rolling
  class Task
    def self.current_ticks
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) * 10e9).to_i
    end

    attr_reader :ticks, :callback

    def initialize(period, &callback)
      @ticks = self.class.current_ticks + (period * 10e9).to_i
      @callback = callback
    end
  end
end
