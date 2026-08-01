# frozen_string_literal: true

require_relative "lib/activeagents/telemetry/version"

Gem::Specification.new do |spec|
  spec.name = "activeagents-telemetry"
  spec.version = ActiveAgents::Telemetry::VERSION
  spec.authors = [ "ActiveAgents" ]
  spec.email = [ "hello@activeagents.ai" ]

  spec.summary = "Shared core for reporting LLM traces to ActiveAgents"
  spec.description = <<~DESC
    The wire format, configuration, and delivery layer behind ActiveAgents
    telemetry. Install an adapter for whatever your app calls the model
    through — activeagents-telemetry-ruby_llm for apps built on RubyLLM —
    and traces land in the ActiveAgents platform or any self-hosted
    ActiveAgent dashboard (POST /v1/traces). Nothing beyond stdlib.
  DESC

  spec.homepage = "https://github.com/activeagents/activeagents-telemetry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "#{spec.homepage}/wiki",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]
end
