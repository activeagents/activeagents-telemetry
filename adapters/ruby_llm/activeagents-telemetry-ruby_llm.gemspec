# frozen_string_literal: true

require_relative "lib/activeagents/telemetry/ruby_llm/version"

Gem::Specification.new do |spec|
  spec.name = "activeagents-telemetry-ruby_llm"
  spec.version = ActiveAgents::Telemetry::RubyLLM::VERSION
  spec.authors = [ "ActiveAgents" ]
  spec.email = [ "hello@activeagents.ai" ]

  spec.summary = "Report RubyLLM chats to an ActiveAgents trace endpoint"
  spec.description = <<~DESC
    Subscribes to RubyLLM's instrumentation events and reports each chat turn
    as a trace — a root span, an llm span, and a span per tool call — to the
    ActiveAgents platform or any self-hosted ActiveAgent dashboard. Works with
    apps built directly on RubyLLM: no ActiveAgent framework dependency.
  DESC

  spec.homepage = "https://github.com/activeagents/activeagents-telemetry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/adapters/ruby_llm",
    "documentation_uri" => "#{spec.homepage}/wiki/RubyLLM",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activeagents-telemetry", "~> 0.1"
  spec.add_dependency "activesupport", ">= 7.0"
end
