# frozen_string_literal: true

require "curses"

module Changelogger
  # +Changelogger::PreviewWindow+ shows scrollable text in a framed window.
  class PreviewWindow
    # +Changelogger::PreviewWindow.new+                 -> PreviewWindow
    #
    # @param [String] title window title
    # @param [String] content initial text
    # @param [Integer] top top row position
    # @param [Integer] left left column position
    # @param [Integer, nil] height window height or computed from screen
    # @param [Integer, nil] width window width or computed from screen
    def initialize(title: "Preview", content: "", top: 1, left: 0, height: nil, width: nil)
      @title = title
      screen_h = Curses.lines
      screen_w = Curses.cols

      @height = height || [screen_h - top, 3].max
      @width  = width  || [screen_w - left, 10].max
      @top    = top
      @left   = left

      @sub_height = @height - 2
      @sub_width  = @width  - 2
      @sub_top    = @top + 1
      @sub_left   = @left + 1

      @offset = 0
      @lines  = (content || "").split("\n")

      build_windows
      redraw
    end

    # +Changelogger::PreviewWindow#update_content+      -> void
    #
    # Replace content and reset scroll to top.
    # @param [String] text new content
    # @return [void]
    def update_content(text)
      @lines  = (text || "").split("\n")
      @offset = 0
      redraw
    end

    # +Changelogger::PreviewWindow#run+                 -> void
    #
    # Enters the input loop. Returns when user closes the preview.
    # @return [void]
    def run
      loop do
        case @sub.getch
        when Curses::Key::UP, "k"
          @offset = [@offset - 1, 0].max
          redraw
        when Curses::Key::DOWN, "j"
          max_off = [@lines.length - @sub_height, 0].max
          @offset = [@offset + 1, max_off].min
          redraw
        when Curses::Key::PPAGE
          @offset = [@offset - @sub_height, 0].max
          redraw
        when Curses::Key::NPAGE
          max_off = [@lines.length - @sub_height, 0].max
          @offset = [@offset + @sub_height, max_off].min
          redraw
        when "g"
          @offset = 0
          redraw
        when "G"
          @offset = [@lines.length - @sub_height, 0].max
          redraw
        when "q", 27
          break
        end
      end
    ensure
      destroy
    end

    private

    # @!visibility private

    def build_windows
      @frame = Curses::Window.new(@height, @width, @top, @left)
      @frame.box
      draw_title
      @frame.refresh

      @sub = @frame.subwin(@sub_height, @sub_width, @sub_top, @sub_left)
      @sub.keypad(true)
      @sub.scrollok(false)
    end

    def draw_title
      title = " #{@title} "
      bar = title.center(@width - 2, "─")
      @frame.setpos(0, 1)
      @frame.addstr(bar[0, @width - 2])
    end

    def redraw
      @sub.erase

      visible = @lines[@offset, @sub_height] || []
      visible.each_with_index do |line, i|
        @sub.setpos(i, 0)
        @sub.addstr(line.ljust(@sub_width, " ")[0, @sub_width])
      end

      (visible.length...@sub_height).each do |i|
        @sub.setpos(i, 0)
        @sub.addstr(" " * @sub_width)
      end

      @sub.refresh
    end

    def destroy
      @sub&.close
      @frame&.close
    rescue StandardError
      # ignore
    end
  end
end
