# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

begin
  require "yard"
  YARD::Rake::YardocTask.new(:yard) do |t|
    t.options = File.exist?(".yardopts") ? File.read(".yardopts").split : []
  end
rescue LoadError
  # yard not installed
end

task default: %i[spec rubocop]
