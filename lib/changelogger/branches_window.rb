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
        File.read(FILENAME)
      end
    end
  end

  # +Changelogger::BranchWindow+ class represents an interface of a graph's window
  class BranchWindow
    attr_reader :selected_shas

    def initialize(max_height: 50, width: nil, top: 1, left: 0)
      screen_height = Curses.lines
      screen_width  = Curses.cols

      @lines  = Graph.build.split("\n")
      @height = [screen_height - 1, max_height].min
      @top    = ((screen_height - @height) / 2).floor + top
      @width  = width || [screen_width - 2, Graph.width + 4].min
      @left   = left

      @sub_height = @height - 2
      @sub_width  = @width  - 2
      @sub_top    = @top + 1
      @sub_left   = @left + 1

      @headers = detect_headers(@lines)
      @selected_header_idx = 0
      @selected_header_idxs = [] # indices into @headers array

      @offset     = 0
      @cursor_row = 0

      @fit_full_block = true

      setup_windows
      ensure_visible
      redraw
    end

    def select_commits
      handle_keyboard_input
      @selected_shas || []
    ensure
      teardown
    end

    private

    def setup_windows
      frame = Curses::Window.new(@height, @width, @top, @left)
      frame.box
      frame.refresh

      @win1 = frame.subwin(@sub_height, @sub_width, @sub_top, @sub_left)
      @win1.keypad(true)
      @win1.scrollok(false)
    end

    def teardown
      Curses.close_screen
    rescue StandardError
      # ignore
    end

    def detect_headers(lines)
      lines.each_index.select { |i| lines[i].match?(/commit [a-f0-9]{7,40}/) }
    end

    def header_line_abs
      @headers[@selected_header_idx] || 0
    end

    def header_sha_at(abs_index)
      line = @lines[abs_index] || ""
      m = line.match(/commit ([a-f0-9]{7,40})/)
      m && m[1]
    end

    def current_commit_range
      start = header_line_abs
      stop  = @headers[@selected_header_idx + 1] || @lines.length
      (start...stop)
    end

    def ensure_visible(fit_full_block: @fit_full_block)
      header_line = header_line_abs
      stop        = @headers[@selected_header_idx + 1] || @lines.length
      block_size  = stop - header_line

      if header_line < @offset
        @offset = header_line
      elsif header_line >= @offset + @sub_height
        @offset = header_line - (@sub_height - 1)
      end

      if fit_full_block && block_size <= @sub_height
        @offset = stop - @sub_height if stop > @offset + @sub_height
        @offset = header_line if header_line < @offset
      end

      @offset = [[@offset, 0].max, [@lines.length - @sub_height, 0].max].min
      @cursor_row = header_line - @offset
    end

    def toggle_selection
      idx = @selected_header_idx
      if @selected_header_idxs.include?(idx)
        @selected_header_idxs.delete(idx)
      else
        @selected_header_idxs << idx
        @selected_header_idxs.sort!
      end
    end

    def selected_shas_from_idxs
      @selected_header_idxs.map { |h_idx| header_sha_at(@headers[h_idx]) }.compact
    end

    def handle_keyboard_input
      loop do
        ch = @win1.getch
        case ch
        when Curses::Key::UP, "k"
          if @selected_header_idx.positive?
            @selected_header_idx -= 1
            ensure_visible
            redraw
          end
        when Curses::Key::DOWN, "j"
          if @selected_header_idx < @headers.length - 1
            @selected_header_idx += 1
            ensure_visible
            redraw
          end
        when Curses::Key::PPAGE
          @selected_header_idx = [@selected_header_idx - 5, 0].max
          ensure_visible
          redraw
        when Curses::Key::NPAGE
          @selected_header_idx = [@selected_header_idx + 5, @headers.length - 1].min
          ensure_visible
          redraw
        when "f"
          @fit_full_block = !@fit_full_block
          ensure_visible
          redraw
        when " "
          toggle_selection
          redraw
        when "\r", "\n", 10, Curses::Key::ENTER
          shas = selected_shas_from_idxs
          if shas.size >= 2
            @selected_shas = shas
            break
          else
            flash_message("Select at least 2 commits (space)")
          end
        when "q", 27
          @selected_shas = []
          break
        else
          # noop
        end
      end
    end

    def flash_message(msg)
      return if @sub_height <= 0 || @sub_width <= 0

      @win1.setpos(@sub_height - 1, 0)
      txt = msg.ljust(@sub_width, " ")[0, @sub_width]
      @win1.attron(Curses::A_BOLD)
      @win1.addstr(txt)
      @win1.attroff(Curses::A_BOLD)
      @win1.refresh
      sleep(0.6)
    end

    def redraw
      ensure_visible
      @win1.erase

      highlight = current_commit_range
      selected_header_abs = @selected_header_idxs.map { |i| @headers[i] }.to_set

      visible = @lines[@offset, @sub_height] || []
      visible.each_with_index do |line, i|
        idx = @offset + i
        @win1.setpos(i, 0)
        text = line.ljust(@sub_width, " ")[0, @sub_width]

        # Mark selected headers with ✓ at the end
        if selected_header_abs.include?(idx)
          mark = " ✓"
          text = text[0, [@sub_width - mark.size, 0].max] + mark
        end

        if highlight.cover?(idx)
          @win1.attron(Curses::A_STANDOUT)
          @win1.addstr(text)
          @win1.attroff(Curses::A_STANDOUT)
        else
          @win1.addstr(text)
        end
      end

      # clear tail lines
      (visible.length...@sub_height).each do |i|
        @win1.setpos(i, 0)
        @win1.addstr(" " * @sub_width)
      end

      @win1.refresh
    end
  end
end
