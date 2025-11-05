# frozen_string_literal: true

require 'curses'
require_relative 'header'
require_relative 'branches_window'

module Changelogger
  # +Changelogger::TUI+ wraps curses lifecycle and runs the side-by-side UI.
  class TUI
    # +Changelogger::TUI.run+                         -> Array<String>, nil
    #
    # Starts curses, draws the header and graph/preview panes, and returns the
    # selected anchor SHAs when the user presses Enter.
    #
    # @return [Array<String>, nil] array of SHAs (2+) or nil if cancelled (q/ESC)
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
        win.select_commits
      ensure
        begin
          Curses.close_screen
        rescue StandardError
          nil
        end
      end
    end
  end
end
