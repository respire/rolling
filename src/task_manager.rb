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
      tasks_filtered = @tasks.select { |task| task.should_fire?(cticks) }
      tasks_filtered.each do |task|
        @tasks.delete task
        Util.safe_execute { task.callback.call }
      end
    end
  end
end
