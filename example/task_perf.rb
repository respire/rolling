# frozen_string_literal: true

require_relative '../src/rolling'

evloop = Rolling::EventLoop.new

capacity = 100_000
counter = 0
on_trigger = proc do
  counter += 1
  if counter == capacity
    Rolling::Util.log_info 'trigger'
    counter = 0
  end
  evloop.add_timer(rand(2.4999..3.4999), &on_trigger)
end

capacity.times { on_trigger.call }

evloop.run
