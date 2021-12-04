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
    # @param [Integer] height Value of window height
    # @param [Integer] width Value of window width
    # @param [Integer] top Value of window position relative to the top of the last
    # @param [Integer] left Value of window position relative to the left of the last
    # @return [object]
    def initialize(height: 50, width: Graph.width + 20, top: 10, left: 0)
      @height = height
      @width = width
      @top = top
      @left = left
      @pos = 0
      @lines = Graph.build.split('\n')
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
      @win1 = win.subwin(@height - 2, @width - 2, @top, @left + 1)
      @win1.keypad true
      #@win1.nodelay = true
      @win1.setpos(1, 1)
      @win1.addstr(Graph.build)
      @win1.refresh
      # @win1.getch
      handle_keyboard_input
    end

    # +Changelogger::BranchWindow#handle_keyboard_input+    -> value
    def handle_keyboard_input
      case @win1.getch
      when Curses::Key::UP, "k"
        @pos -= 1 unless @pos <= 0
        scroll
      when Curses::Key::DOWN, "j"
        @pos += 1 unless @pos >= @lines.count - 1 # lines(?)
        scroll
      when "q"
        exit(0)
      end
    end

    # +Changelogger::BranchWindow#scroll+                   -> value
    def scroll
      @pos ||= 0
      @win1.clear
      @win1.setpos(1, 1)
      @lines.slice(@pos, @height - 1).each { |line| @win1 << "#{line}\n" }
      @win1.refresh
    end

    def move_highlight_up; end

    def move_highlight_down; end
  end
end
