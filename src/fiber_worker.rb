# frozen_string_literal: true

module Rolling
  class FiberWorker
    attr_reader :resume_callback

    def initialize
      fiber = Fiber.new do |task|
        loop do
          if task
            begin
              ret = [:ok, task[0].call(*task[1])]
            rescue ::Exception => e
              ret = [:error, e]
            end
          else
            ret = [:idle]
          end
          task = Fiber.yield ret
        end
      end
      @resume_callback = ->(ret) { fiber.resume(ret) }
      @fiber = fiber
    end

    def alive?
      @fiber.alive?
    end

    def post(blk, *args)
      @fiber.resume [blk, args]
    end
  end
end
