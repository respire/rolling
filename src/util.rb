# frozen_string_literal: true

module Rolling
  module UtilImpl
    def safe_execute(errback = nil)
      yield
    rescue ::StandardError => e
      log_exception(e)
      safe_execute { errback.call(e) } if errback
    end

    def log_info(*args)
      if args.length == 1
        logger.info args.first
      elsif args.length > 1
        pattern = args.shift
        logger.info format(pattern, *args)
      end
    end

    def log_exception(e)
      pipe = [e.inspect]

      pipe.concat(e.backtrace.map { |row| "\t\t#{row}" }) if e.backtrace

      logger.error pipe.join("\n")
    end

    def logger
      # TODO: multithread-friendly logger should be introduced in future so as to support reactor-per-thread model.
      @logger ||= ::Logger.new(STDOUT)
    end
  end

  module Util
    extend UtilImpl
  end
end
