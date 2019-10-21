# frozen_string_literal: true

require_relative '../src/rolling'

evloop = Rolling::EventLoop.new

capacity = 1024 * 1024
counter = 0
on_trigger = proc do
  counter += 1
  if counter == capacity
    Rolling::Util.log_info 'trigger'
    counter = 0
  end
  evloop.add_timer(3 + rand(-0.4999..0.4999), &on_trigger)
end

capacity.times { on_trigger.call }

evloop.run
