# frozen_string_literal: true

module Rolling
  class TaskManager
    def initialize
      @tasks = []
      @dirty = false
    end

    def empty?
      @tasks.empty?
    end

    def append(period, &callback)
      task = Task.new(period, &callback)
      @dirty = true
      @tasks << task
    end

    def fire
      cticks = Task.current_ticks

      if @dirty
        @tasks.sort! { |lhs, rhs| lhs.ticks - rhs.ticks }
        @dirty = false
      end

      purge_idx = -1
      @tasks.each do |task|
        break unless task.ticks <= cticks

        purge_idx += 1
      end

      unless purge_idx == -1
        tasks_to_trigger = @tasks.slice!(0..purge_idx)
        tasks_to_trigger.each do |task|
          Util.safe_execute { task.callback.call }
        end
      end

      next_task = @tasks.first
      return unless next_task

      next_dticks = next_task.ticks - Task.current_ticks
      next_dticks = next_dticks * 1.0 / 10e9
      next_dticks < 0.001 ? 0.001 : next_dticks
    end
  end
end
