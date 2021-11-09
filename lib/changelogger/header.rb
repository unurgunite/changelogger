# frozen_string_literal: true

module Changelogger # :nodoc:
  # +Changelogger::Header+ class is an interface for header of TUI
  class Header
    
    # +Changelogger::Header.new+                    -> object
    #
    # @return [object]
    # An alias to {Changelogger::Header}'s class method +standard_header+
    def initialize
      header_win
      line
    end

    private

    # +Changelogger::Header.header_win+             -> object
    #
    # @private
    # @return [object]
    # +Changelogger::Header.header_win+ method is used to initialize header's frame
    def header_win
      @height = 0
      @width = Curses.cols
      @top = 0
      @left = 0
      @header_win = Curses::Window.new(@height, @width, @top, @left)
      @header_win.box(" ", " ", " ")
    end

    # +Changelogger::Header.line+                   -> object
    #
    # @private
    # @return [object]
    # +Changelogger::Header.line+ method is used to draw a line with gem's name and its version
    def line
      line = @header_win.subwin(0, @width, @top, @left)
      line.addstr(" Changelogger #{Changelogger::VERSION} ".center(@width, "="))
      line.refresh
      line.getch
    end

    class << self
      alias standard_header new
    end
    #     # +Changelogger::Header.standard_header+  -> object
    #     #
    #     # @return [object]
    #     # +Changelogger::Header.line+ method generates util's header object
    #     def self.standard_header
    #       header_win
    #       line
    #     end
  end
end
