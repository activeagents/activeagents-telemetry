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
        @send_threads = []
        @shutdown = false
      end

      # Enqueues a trace, flushing if the batch is full. `sync: true` skips the
      # buffer: that call's traces are delivered in the calling thread before
      # it returns, so a short-lived process can hand a trace over before it
      # exits, and whatever the buffer already holds stays on its own schedule.
      # @return [Boolean] whether any of the traces were accepted
      def report(traces, sync: false)
        return false if @shutdown

        accepted = normalize(traces).select { sample_trace? }
        return false if accepted.empty?
        return false unless configuration.enabled? && configuration.configured?

        if sync
          body = begin
            payload_for(accepted)
          rescue StandardError => e
            log("failed to build trace payload: #{e.class}: #{e.message}")
            return false
          end
          deliver(body)
          return true
        end

        batch = nil
        @mutex.synchronize do
          @buffer.concat(accepted)
          batch = @buffer.slice!(0..) if @buffer.size >= configuration.batch_size
          start_flusher
        end
        deliver_batch(batch) if batch
        true
      end

      # Delivers everything buffered, blocking until done.
      def flush
        batch = @mutex.synchronize { @buffer.slice!(0..) }
        deliver_batch(batch, blocking: true) unless batch.empty?
        nil
      end

      # Flushes, waits out in-flight sends, and stops the background thread —
      # traces reported just before process exit are delivered, not dropped.
      # Idempotent.
      def shutdown
        @shutdown = true
        flush
        @mutex.synchronize { @send_threads.dup }.each { |thread| thread.join(configuration.timeout) }
        @flusher&.kill
        @flusher = nil
      end

      private

      def deliver_batch(batch, blocking: false)
        body = payload_for(batch)
        return deliver(body) if blocking || !configuration.async?

        thread = Thread.new { deliver(body) }
        @mutex.synchronize do
          @send_threads.select!(&:alive?)
          @send_threads << thread
        end
        thread
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
