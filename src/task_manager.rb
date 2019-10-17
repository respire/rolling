# frozen_string_literal: true

module Rolling
  class TaskManager
    def initialize
      @tasks = SortedSet.new
    end

    def append(period, &callback)
      @tasks.add Task.new(period, &callback)
    end

    def fire
      cticks = Task.current_ticks
      tasks_fired = []
      @tasks.each do |task|
        break unless task.should_fire?(cticks)

        tasks_fired << task
        Util.safe_execute { task.callback.call }
      end
      @tasks.subtract(tasks_fired) unless tasks_fired.empty?
      next_task = @tasks.first
      return unless next_task

      next_dticks = next_task.ticks - Task.current_ticks
      next_dticks < 0.001 ? 0.001 : next_dticks
    end
  end
end
