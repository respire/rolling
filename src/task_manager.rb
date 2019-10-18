# frozen_string_literal: true

module Rolling
  class TaskManager
    def initialize
      @tasks = SortedSet.new
    end

    def empty?
      @tasks.empty?
    end

    def append(period, &callback)
      @tasks.add Task.new(period, &callback)
    end

    def fire
      cticks = Task.current_ticks
      tasks_to_trigger = []
      @tasks.each do |task|
        break unless task.should_fire?(cticks)

        tasks_to_trigger << task
      end

      unless tasks_to_trigger.empty?
        @tasks.subtract(tasks_to_trigger)
        tasks_to_trigger.each do |task|
          Util.safe_execute { task.callback.call }
        end
      end

      next_task = @tasks.first
      return unless next_task

      next_dticks = next_task.ticks - Task.current_ticks
      next_dticks < 0.001 ? 0.001 : next_dticks
    end
  end
end
