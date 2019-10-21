# frozen_string_literal: true

module Rolling
  class TaskManager
    def initialize
      @queue = TaskQueue.new
    end

    def empty?
      @queue.empty?
    end

    def append(period, &callback)
      task = Task.new(period, &callback)
      @queue.add task
    end

    def fire
      cticks = Task.current_ticks

      next_task = @queue.first

      if next_task && next_task.ticks <= cticks
        tasks_to_trigger = []
        while next_task && next_task.ticks <= cticks
          tasks_to_trigger << @queue.pop
          next_task = @queue.first
        end
        tasks_to_trigger.each do |task|
          Util.safe_execute { task.callback.call }
        end
      end

      return unless next_task

      next_dticks = next_task.ticks - Task.current_ticks
      next_dticks = next_dticks * 1.0 / 10e9
      next_dticks < 0.001 ? 0.001 : next_dticks
    end
  end
end
