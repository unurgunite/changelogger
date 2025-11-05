# frozen_string_literal: true

module Changelogger
  # +Changelogger::Header+ draws the top header (title/version) of the TUI.
  class Header
    # +Changelogger::Header.new+                    -> Changelogger::Header
    #
    # Draws a single header line with the gem name and version.
    #
    # @param [Integer] height window height
    # @param [Integer] width window width
    # @param [Integer] top top position
    # @param [Integer] left left position
    # @return [Header]
    def initialize(height: 0, width: Curses.cols, top: 0, left: 0)
      @height = height
      @width = width
      @top = top
      @left = left
      header_win
      line
    end

    private

    # +Changelogger::Header.header_win+             -> void
    # @private
    # Initializes the header frame.
    # @return [void]
    def header_win
      @header_win = Curses::Window.new(@height, @width, @top, @left)
      @header_win.box(' ', ' ', ' ')
    end

    # +Changelogger::Header.line+                   -> void
    # @private
    # Renders the header text.
    # @return [void]
    def line
      line = @header_win.subwin(@height, @width, @top, @left)
      line.addstr(" Changelogger #{Changelogger::VERSION} ".center(@width, '='))
      line.refresh
    end
  end
end
