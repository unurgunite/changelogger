# frozen_string_literal: true

module Changelogger
  # +Changelogger::Graph+ class represents an interface of graph object, which renders in a separate window
  class Graph
    class << self
      # Name of the file, where to store graphs
      FILENAME = ".graph"

      # +Changelogger::Graph.width+                         -> Integer
      #
      # +Changelogger::Graph.width+ returns the size of the biggest line in a file to then set this value as
      # default window object width attribute
      # @return [Integer]
      def width
        File.open(FILENAME, "w") { |file| file.write(`git log --graph`) }
        IO.foreach(FILENAME).max_by(&:length).size
      end

      # +Changelogger::Graph.build+                         -> String
      #
      # +Changelogger::Graph.build+ field builds graph object in a separate window
      # @return [String]
      def build
        "No such file: #{Dir.pwd}/#{FILENAME}" unless File.file?(FILENAME)
        File.read(".graph")
      end
    end
  end

  # +Changelogger::BranchWindow+ class represents an interface of a graph's window
  class BranchWindow
    # +Changelogger::BranchWindow.new+                      -> obj
    #
    # @param [Integer] max_height Value of window height if not limited by screen height
    # @param [Integer] width Value of window width
    # @param [Integer] top Value of window position relative to the top of the last
    # @param [Integer] left Value of window position relative to the left of the last
    # @return [object]
    def initialize(max_height: 50, width: Graph.width + 20, top: 1, left: 0)
      screen_height = Curses.lines

      @height = [screen_height - 1, max_height].min
      @top = ((screen_height - @height) / 2).floor + top
      @width = width
      @left = left

      @pos = 0
      @sub_height = @height - 2
      @sub_width = @width - 2
      @sub_top = @top + 1
      @sub_left = @left + 1

      @lines = Graph.build.split("\n")
      branches
    end

    private

    # +Changelogger::BranchWindow#branches+                 -> value
    #
    # +Changelogger::BranchWindow#branches+ field is used to prepare window to show graph
    # @private
    # @return [Object]
    def branches
      win = Curses::Window.new(@height, @width, @top, @left)
      win.box
      win.scrollok true
      win.refresh

      @win1 = win.subwin(@sub_height, @sub_width, @sub_top, @sub_left)
      @win1.keypad true

      redraw
      handle_keyboard_input
    end

    # +Changelogger::BranchWindow#handle_keyboard_input+    -> value
    #
    # +Changelogger::BranchWindow#handle_keyboard_input+ handles keyboard input to scroll the division
    # @private
    # @return [Object]
    def handle_keyboard_input
      loop do
        case @win1.getch
        when Curses::Key::UP, "k"
          @pos -= 1 unless @pos <= 0
          redraw
        when Curses::Key::DOWN, "j"
          @pos += 1 unless @pos >= @lines.count - @sub_height
          redraw
        when "q"
          exit(0)
        end
      end
    end

    # +Changelogger::BranchWindow#redraw+                   -> value
    #
    # +Changelogger::BranchWindow#redraw+ rerender window content
    # @private
    # @return [Object]
    def redraw
      @pos ||= 0
      @win1.setpos(0, 0)

      headers = @lines.each_with_index.filter_map { |line, i| i if line.match?(/commit [a-z0-9]+/) }
      commits = @lines.each_with_index.reduce [] do |acc, (line, i)|
        if headers.include? i
          [*acc, [line]]
        else
          [*acc[0..-2], [*acc.last, line]]
        end
      end

      @win1.attron(Curses::A_STANDOUT)
      @win1.addstr(@lines.slice(@pos, @sub_height).map { |line| line.ljust @sub_width - 1, " " }.join("\n"))
      @win1.attroff(Curses::A_STANDOUT)

      @win1.refresh
    end

    def move_highlight_up; end

    def move_highlight_down; end
  end
end
