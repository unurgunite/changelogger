# frozen_string_literal: true

require "curses"

module Changelogger
  class PreviewWindow
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

    def update_content(text)
      @lines  = (text || "").split("\n")
      @offset = 0
      redraw
    end

    def run
      loop do
        case @sub.getch
        when Curses::Key::UP, "k"
          @offset = [@offset - 1, 0].max
          redraw
        when Curses::Key::DOWN, "j"
          max_off = [@lines.length - @sub_height, 0].max
          @offset = [@offset + 1, max_off].max([@offset + 1]).min
          @offset = [@offset, max_off].min
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
        when "q", 27 # p or q or ESC closes preview
          break
        when nil
          # ignore
        else
          # ignore
        end
      end
    ensure
      destroy
    end

    private

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

      # clear remaining rows
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
