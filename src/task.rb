# frozen_string_literal: true

module Rolling
  class Task
    def self.current_ticks
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    attr_reader :ticks, :callback

    def initialize(period, &callback)
      @ticks = self.class.current_ticks + period
      @callback = callback
    end

    def <=>(other)
      dt = @ticks <=> other.ticks
      dt.zero? ? (@callback.object_id <=> other.callback.object_id) : dt
    end

    def should_fire?(cticks)
      @ticks <= cticks
    end
  end
end
