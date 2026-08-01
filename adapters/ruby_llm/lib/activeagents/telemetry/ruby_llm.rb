# frozen_string_literal: true

require "active_support"
require "active_support/notifications"

require "activeagents/telemetry"

require_relative "ruby_llm/version"

module ActiveAgents
  module Telemetry
    # Reports RubyLLM chats to an ActiveAgents-compatible trace endpoint.
    #
    # Requires RubyLLM.config.instrumenter = ActiveSupport::Notifications
    # (RubyLLM 1.x; 2.x wires this up under Rails).
    #
    # One trace per conversation turn: a root span, an llm span covering the
    # whole provider loop, and a tool span per tool_call.ruby_llm event.
    #
    # RubyLLM emits a chat.ruby_llm event per provider round, and the two
    # generations of the gem arrange those rounds differently: through 1.x a
    # tool round recurses inside the enclosing event, while 2.x drives a flat
    # `step until complete?` loop whose rounds are siblings with tool calls
    # firing between them. Rounds are therefore accumulated and flushed on the
    # round that ends the turn — the one that errors or answers without
    # requesting tools — which yields the same trace under both arrangements.
    # Tokens are summed per round from the assistant messages that round added,
    # so a repeated event-level count is never double counted.
    #
    # Tool arguments and results are never sent; error messages are truncated.
    module RubyLLM
      AGENT_KEY = :activeagents_telemetry_ruby_llm_agent
      STATE_KEY = :activeagents_telemetry_ruby_llm_state
      TOOL_STARTED_AT_KEY = :_activeagents_telemetry_started_at
      SDK_NAME = "activeagents-telemetry-ruby_llm"
      # A turn that never reaches a final round (a halted tool call, or an app
      # driving RubyLLM 2.x's `step` by hand) would otherwise accumulate forever.
      MAX_TURN_SECONDS = 600

      DEFAULT_AGENT = { name: "RubyLLM::Chat", action: "chat" }.freeze

      State = Struct.new(:depth, :started_at, :tool_spans, :rounds, :tokens, :chat_key)

      class << self
        # Subscribes to RubyLLM's instrumentation.
        #
        # Destination settings fall back to ActiveAgents::Telemetry.configuration,
        # so an app that already called `ActiveAgents::Telemetry.configure` can
        # call this with no arguments at all.
        #
        # agent_resolver: optional callable receiving the chat event payload and
        # returning { name:, action: }, so traffic can be attributed from an
        # initializer alone; an enclosing with_agent block still wins. RubyLLM
        # carries no application identity on the payload — neither RubyLLM::Agent
        # nor an acts_as_chat record reaches the instrumenter — so unattributed
        # traffic reports as RubyLLM::Chat.
        def subscribe!(api_key: nil, endpoint: nil, service_name: nil, environment: nil,
                       agent_resolver: nil, async: nil, configuration: nil)
          @configuration = configuration || Telemetry.configuration.dup
          @configuration.api_key = api_key unless api_key.nil?
          @configuration.endpoint = endpoint unless endpoint.nil?
          @configuration.service_name = service_name unless service_name.nil?
          @configuration.environment = environment unless environment.nil?
          @configuration.async = async unless async.nil?

          @agent_resolver = agent_resolver
          @reporter = Reporter.new(@configuration, sdk_name: SDK_NAME, sdk_version: VERSION)

          @subscriptions ||= [
            ActiveSupport::Notifications.subscribe("chat.ruby_llm", ChatSubscriber.new),
            ActiveSupport::Notifications.subscribe("tool_call.ruby_llm", ToolCallSubscriber.new)
          ]
        end

        def unsubscribe!
          Array(@subscriptions).each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
          @subscriptions = nil
        end

        def configuration
          @configuration ||= Telemetry.configuration
        end

        def reporter
          @reporter ||= Reporter.new(configuration, sdk_name: SDK_NAME, sdk_version: VERSION)
        end

        attr_writer :reporter

        # Attributes traces inside the block to a named agent/action.
        def with_agent(name, action: "chat")
          previous = Thread.current[AGENT_KEY]
          Thread.current[AGENT_KEY] = { name: name, action: action }
          yield
        ensure
          Thread.current[AGENT_KEY] = previous
        end

        def state
          Thread.current[STATE_KEY] ||= State.new(0, nil, [], 0, Span::ZERO_TOKENS.dup, nil)
        end

        def clear_state
          Thread.current[STATE_KEY] = nil
        end

        # Reports whatever the current turn has accumulated. Apps that drive
        # RubyLLM 2.x's `step`/`run_tools` themselves can call this to close a
        # turn that ends while tool calls are still pending.
        def flush!(payload = {})
          turn = Thread.current[STATE_KEY]
          return if turn.nil? || turn.rounds.zero?

          clear_state
          report_turn(payload, turn)
        end

        def begin_round(payload)
          turn = state
          if turn.depth.zero?
            chat_key = payload[:chat].object_id
            flush! if turn.rounds.positive? && (turn.chat_key != chat_key || turn_expired?(turn))
            turn = state
            turn.chat_key = chat_key
            turn.started_at ||= Time.now
          end
          turn.depth += 1
        end

        def finish_round(payload)
          turn = state
          turn.depth -= 1
          return unless turn.depth.zero?

          turn.rounds += 1
          accumulate_tokens(turn, payload)
          flush!(payload) if payload[:exception_object] || !payload[:tool_call]
        end

        def build_tool_span(payload, started_at, finished_at)
          error = payload[:exception_object]
          span = Span.new(
            "tool.#{payload[:tool_name]}",
            type: "tool",
            start_time: started_at,
            attributes: { "tool.name" => payload[:tool_name].to_s, "tool.call_id" => payload[:tool_call_id].to_s }
          )
          span.record_error(error, message_limit: configuration.error_message_limit) if error
          span.finish(at: finished_at)
        end

        private

        def report_turn(payload, turn)
          agent = Thread.current[AGENT_KEY] || resolve_agent(payload) || DEFAULT_AGENT
          started_at = turn.started_at || Time.now
          finished_at = Time.now
          error = payload[:exception_object]

          trace = Trace.new(
            service_name: configuration.resolved_service_name,
            environment: configuration.resolved_environment,
            resource_attributes: configuration.resource_attributes
          )

          root = trace.span(
            "#{agent[:name]}.#{agent[:action]}", type: "root", start_time: started_at,
            attributes: {
              "agent.class" => agent[:name],
              "agent.action" => agent[:action],
              "agent.provider" => payload[:provider].to_s,
              "agent.model" => payload[:model].to_s
            }
          )

          llm = trace.span(
            "llm.generate", type: "llm", parent: root, start_time: started_at,
            attributes: {
              "llm.provider" => payload[:provider].to_s,
              "llm.model" => payload[:model].to_s,
              "llm.rounds" => turn.rounds,
              "llm.streaming" => payload[:streaming] || false
            }
          )
          llm.add_tokens(turn.tokens)

          [ root, llm ].each do |span|
            span.record_error(error, message_limit: configuration.error_message_limit) if error
            span.finish(at: finished_at)
          end

          turn.tool_spans.each do |tool_span|
            tool_span.parent_span_id = llm.span_id
            trace.add_span(tool_span)
          end

          reporter.report(trace)
        end

        def turn_expired?(turn)
          turn.started_at.nil? || (Time.now - turn.started_at) > MAX_TURN_SECONDS
        end

        def accumulate_tokens(turn, payload)
          turn.tokens = turn.tokens.merge(token_totals(payload)) { |_key, carried, added| carried + added }
        end

        def resolve_agent(payload)
          agent = @agent_resolver&.call(payload)
          return unless agent.is_a?(Hash) && !agent[:name].to_s.empty?

          { name: agent[:name], action: agent[:action] || "chat" }
        rescue StandardError => e
          warn "[#{SDK_NAME}] agent_resolver failed: #{e.class}: #{e.message}"
          nil
        end

        def token_totals(payload)
          initial_count = Array(payload[:input_messages]).size
          new_messages = Array(payload[:messages_after])[initial_count..] || []
          assistant_messages = new_messages.select { |message| message.respond_to?(:role) && message.role.to_s == "assistant" }

          tokens = {
            "input" => sum_tokens(assistant_messages, :input_tokens),
            "output" => sum_tokens(assistant_messages, :output_tokens),
            "thinking" => sum_tokens(assistant_messages, :thinking_tokens)
          }
          tokens["total"] = tokens.values.sum
          tokens
        end

        def sum_tokens(messages, method_name)
          messages.sum { |message| message.respond_to?(method_name) ? message.public_send(method_name).to_i : 0 }
        end
      end

      # Evented ActiveSupport::Notifications subscriber; finish fires even when
      # the instrumented block raises, with the exception on the payload.
      class ChatSubscriber
        def start(_name, _id, payload)
          RubyLLM.begin_round(payload)
        rescue StandardError => e
          warn "[#{SDK_NAME}] #{e.class}: #{e.message}"
        end

        def finish(_name, _id, payload)
          RubyLLM.finish_round(payload)
        rescue StandardError => e
          warn "[#{SDK_NAME}] #{e.class}: #{e.message}"
          RubyLLM.clear_state
        end
      end

      class ToolCallSubscriber
        def start(_name, _id, payload)
          payload[TOOL_STARTED_AT_KEY] = Time.now
        end

        def finish(_name, _id, payload)
          started_at = payload.delete(TOOL_STARTED_AT_KEY) || Time.now
          RubyLLM.state.tool_spans << RubyLLM.build_tool_span(payload, started_at, Time.now)
        rescue StandardError => e
          warn "[#{SDK_NAME}] #{e.class}: #{e.message}"
        end
      end
    end
  end
end
