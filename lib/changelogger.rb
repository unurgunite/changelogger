# frozen_string_literal: true

# +Changelogger+ is the root namespace for the gem. It exposes the version and error class.
module Changelogger
  # +Changelogger::Error+ is a generic error raised by this library.
  class Error < StandardError; end
end

require_relative 'changelogger/version'
