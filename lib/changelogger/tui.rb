# frozen_string_literal: true

require "curses"
require_relative "header"
require_relative "branches_window"

module Changelogger
  class TUI
    def self.run
      Curses.init_screen
      Curses.cbreak
      Curses.noecho
      Curses.curs_set(0)
      begin
        begin
          Curses.start_color
          Curses.use_default_colors if Curses.respond_to?(:use_default_colors)
        rescue StandardError
        end
        Changelogger::Header.new
        win = Changelogger::BranchWindow.new
        win.select_commits # returns nil on cancel, [] or [shas...] on finish
      ensure
        # BranchWindow already closes the screen on exit, but ensure anyway:
        begin
          Curses.close_screen
        rescue StandardError
          nil
        end
      end
    end
  end
end
