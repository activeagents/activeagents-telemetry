# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.verbose = true
end

desc "Run the adapter test suites"
task :test_adapters do
  Dir["adapters/*"].select { |path| File.directory?(path) }.each do |adapter|
    puts "\n== #{adapter} =="
    Dir.chdir(adapter) { ruby "-Ilib -Itest -e 'Dir[\"test/**/test_*.rb\"].each { |f| require File.expand_path(f) }'" }
  end
end

desc "Run every suite in the repo"
task test_all: %i[test test_adapters]

desc "Build every gem in the repo into pkg/"
task :build_all do
  require "fileutils"
  FileUtils.mkdir_p("pkg")
  root = Dir.pwd

  Dir["*.gemspec", "adapters/*/*.gemspec"].each do |spec|
    dir = File.dirname(spec)
    Dir.chdir(dir) do
      sh "gem build #{File.basename(spec)}"
      Dir["*.gem"].each { |gem| FileUtils.mv(gem, File.join(root, "pkg", gem)) }
    end
  end

  puts "\nBuilt:"
  Dir["pkg/*.gem"].sort.each { |gem| puts "  #{gem}" }
  puts "\nPublish with:  gem push pkg/<name>.gem"
end

task default: :test_all
