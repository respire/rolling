# frozen_string_literal: true

module Rolling
  class TaskQueue
    def initialize
      @tree = [nil]
      @size = 0
    end

    def empty?
      @size.zero?
    end

    def add(task)
      @tree << task
      @size += 1

      # adjust ordering
      k = @size
      while k > 1
        c = k / 2
        break unless @tree[c].ticks > @tree[k].ticks

        swap(k, c)
        k = c
      end
    end

    def first
      @tree[1]
    end

    def pop
      top = @tree[1]
      swap(1, @size)
      @tree.pop
      @size -= 1

      # rearrange
      k = 1
      loop do
        c = 2 * k
        break unless @size >= c

        c += 1 if c < @size && @tree[c].ticks > @tree[c + 1].ticks

        break unless @tree[k].ticks > @tree[c].ticks

        swap(k, c)
        k = c
      end

      top
    end

    private

    def swap(i, j)
      # not a good swap function, but it's enough for now :(
      tmp = @tree[i]
      @tree[i] = @tree[j]
      @tree[j] = tmp
    end
  end
end
