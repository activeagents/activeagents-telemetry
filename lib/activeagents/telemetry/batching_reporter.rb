# frozen_string_literal: true

module ActiveAgents
  module Telemetry
    # A Reporter that buffers traces and delivers them in batches — fewer
    # HTTP requests under sustained traffic, at the cost of traces arriving
    # up to flush_interval seconds late.
    #
    # A full buffer (configuration.batch_size) flushes immediately; a
    # background thread flushes whatever accumulated every
    # configuration.flush_interval seconds. Call #shutdown before process
    # exit or the tail of the buffer is lost.
    #
    # Sampling happens on enqueue, so a dropped trace never occupies buffer
    # space; enabled?/configured? are also checked on enqueue AND inherited
    # from Reporter#report at delivery time.
    class BatchingReporter < Reporter
      def initialize(configuration, **options)
        super
        @buffer = []
        @mutex = Mutex.new
        @flusher = nil
        @shutdown = false
      end

      # Enqueues a trace, flushing if the batch is full.
      def report(traces)
        return if @shutdown

        accepted = Array(traces).reject { |trace| trace.respond_to?(:empty?) && trace.empty? }
                                .select { configuration.sample? }
        return if accepted.empty?
        return unless configuration.enabled? && configuration.configured?

        batch = nil
        @mutex.synchronize do
          @buffer.concat(accepted)
          batch = @buffer.slice!(0..) if @buffer.size >= configuration.batch_size
          start_flusher
        end
        deliver_batch(batch) if batch
        nil
      end

      # Delivers everything buffered, blocking until done.
      def flush
        batch = @mutex.synchronize { @buffer.slice!(0..) }
        deliver_batch(batch, blocking: true) unless batch.empty?
        nil
      end

      # Flushes and stops the background thread. Idempotent.
      def shutdown
        @shutdown = true
        flush
        @flusher&.kill
        @flusher = nil
      end

      private

      def deliver_batch(batch, blocking: false)
        body = payload_for(batch)
        blocking || !configuration.async? ? deliver(body) : Thread.new { deliver(body) }
      rescue StandardError => e
        log("failed to build trace payload: #{e.class}: #{e.message}")
      end

      # Lazily started so a reporter constructed at boot in a process that
      # never traces (a console, a one-off rake task) spawns no thread.
      def start_flusher
        return if @flusher&.alive? || @shutdown

        @flusher = Thread.new do
          Thread.current.name = "activeagents-telemetry-flusher"
          until @shutdown
            sleep(configuration.flush_interval)
            flush
          end
        end
      end
    end
  end
end
