# frozen_string_literal: true

module Changelogger
  # +Changelogger::Header+ class is an interface for header of TUI
  class Header
    # +Changelogger::Header.new+                    -> value
    #
    # @param [Integer] height Value of window height
    # @param [Integer] width Value of window width
    # @param [Integer] top Value of window position relative to the top of the last
    # @param [Integer] left Value of window position relative to the left of the last
    # @return [Object]
    def initialize(height: 0, width: Curses.cols, top: 0, left: 0)
      @height = height
      @width = width
      @top = top
      @left = left
      header_win
      line
    end

    private

    # +Changelogger::Header.header_win+             -> value
    #
    # @private
    # @return [Object]
    # +header_win+ method is used to initialize header's frame
    def header_win
      @header_win = Curses::Window.new(@height, @width, @top, @left)
      @header_win.box(" ", " ", " ")
    end

    # +Changelogger::Header.line+                   -> value
    #
    # @private
    # @return [Object]
    # +line+ method is used to draw a line with gem's name and its version
    def line
      line = @header_win.subwin(@height, @width, @top, @left)
      line.addstr(" Changelogger #{Changelogger::VERSION} ".center(@width, "="))
      line.refresh
    end
  end
end
