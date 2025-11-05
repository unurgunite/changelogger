# frozen_string_literal: true

require 'curses'
require_relative 'git'
require_relative 'versioner'
require_relative 'changelog_generator'
require_relative 'repo_info'

module Changelogger
  # +Changelogger::Graph+ caches `git log --graph` output for rendering.
  class Graph
    class << self
      # +Changelogger::Graph::FILENAME+ stores the graph cache file name.
      FILENAME = '.graph'

      # +Changelogger::Graph.ensure!+                 -> void
      #
      # Regenerates the graph cache file from the current repository.
      # @return [void]
      def ensure!
        content = `git log --graph --decorate=short --date=short --pretty=format:'%h %d %s' 2>/dev/null`
        if content.nil? || content.strip.empty?
          content = "(no git graph available — empty repo or not a git repository)\n"
        end
        File.write(FILENAME, content)
      rescue StandardError => e
        File.write(FILENAME, "(error generating graph: #{e.message})\n")
      end

      # +Changelogger::Graph.width+                   -> Integer
      #
      # Returns the width of the widest graph line (used to size the pane).
      # @return [Integer]
      def width
        ensure! unless File.exist?(FILENAME)
        ensure!
        max = 1
        File.foreach(FILENAME) { |line| max = [max, line.rstrip.length].max }
        max
      end

      # +Changelogger::Graph.build+                   -> String
      #
      # Reads the cached graph content (regenerates if missing).
      # @return [String]
      def build
        ensure! unless File.exist?(FILENAME)
        File.read(FILENAME)
      end
    end
  end

  # +Changelogger::BranchWindow+ is the left-right split TUI with live preview.
  class BranchWindow
    # @return [Array<String>, nil] selected SHAs after Enter, or nil if cancelled
    attr_reader :selected_shas

    # Color pair IDs used within curses
    CP_HELP      = 2
    CP_HIGHLIGHT = 3  # current cursor commit block
    CP_SELECTED  = 4  # selected anchor commit header
    CP_SEP       = 5  # thin separators
    CP_ALT       = 6  # zebra alt shading

    # +Changelogger::BranchWindow.new+               -> Changelogger::BranchWindow
    #
    # Builds the UI panes (graph on the left, preview on the right) and prepares
    # state for selection and scrolling.
    #
    # @param [Integer] max_height maximum height for the panes
    # @param [Integer] top top offset
    # @param [Integer] left left offset
    # @param [Integer, nil] left_width optional fixed width for the left pane
    def initialize(max_height: 50, top: 1, left: 0, left_width: nil)
      @top   = top
      @left  = left
      @width = Curses.cols - @left
      screen_height = Curses.lines
      @height = [screen_height - @top, max_height].min

      @repo = Changelogger::Repo.info

      @lines = Graph.build.split("\n")
      preferred_left = Graph.width + 4
      @left_min  = 24
      @right_min = 28
      @left_w = compute_left_width(requested_left: left_width || preferred_left)

      # Graph state
      @headers = detect_headers(@lines)
      @selected_header_idx  = 0
      @selected_header_idxs = []
      @offset          = 0
      @fit_full_block  = true
      @zebra_blocks    = true

      recompute_blocks!

      # Preview state
      @commits = Changelogger::Git.commits
      @preview_lines  = []
      @preview_offset = 0

      @focus = :left
      @cancelled = false

      setup_windows
      init_colors
      update_titles
      update_preview(reset_offset: true)
      ensure_visible
      redraw
    end

    # +Changelogger::BranchWindow#select_commits+    -> Array<String>, nil
    #
    # Enters the TUI input loop and returns when user confirms or cancels.
    # @return [Array<String>, nil] anchor SHAs (2+ required) or nil when cancelled
    def select_commits
      handle_keyboard_input
      @cancelled ? nil : (@selected_shas || [])
    ensure
      teardown
    end

    private

    # @!visibility private

    # Compute left pane width, respecting min widths for both panes.
    # @param [Integer] requested_left
    # @return [Integer]
    def compute_left_width(requested_left:)
      w = @width
      lw = requested_left.to_i
      [[lw, @left_min].max, w - @right_min].min
    end

    # Create frames and subwindows for both panes.
    # @return [void]
    def setup_windows
      destroy_windows

      @left_frame = Curses::Window.new(@height, @left_w, @top, @left)
      @left_frame.box
      @left_sub = @left_frame.subwin(@height - 2, @left_w - 2, @top + 1, @left + 1)
      @left_sub.keypad(true)
      @left_sub.scrollok(false)

      right_w = @width - @left_w
      right_x = @left + @left_w
      @right_frame = Curses::Window.new(@height, right_w, @top, right_x)
      @right_frame.box
      @right_sub = @right_frame.subwin(@height - 2, right_w - 2, @top + 1, right_x + 1)
      @right_sub.keypad(true)
      @right_sub.scrollok(false)

      @left_frame.refresh
      @right_frame.refresh
    end

    # Close subwindows/frames and close the curses screen.
    # @return [void]
    def destroy_windows
      @left_sub&.close
      @left_frame&.close
      @right_sub&.close
      @right_frame&.close
    rescue StandardError
      # ignore
    end

    # Cleanup hook called when leaving the TUI.
    # @return [void]
    def teardown
      destroy_windows
      Curses.close_screen
    rescue StandardError
      # ignore
    end

    # Update titles with repo name/branch/HEAD and remote slug/identifier.
    # @return [void]
    def update_titles
      dirty = @repo.dirty ? '*' : ''
      left_title = " Graph — #{@repo.name} [#{@repo.branch}@#{@repo.head_short}#{dirty}] "
      draw_title(@left_frame, left_title)
      right_id = @repo.remote_slug || @repo.name
      right_title = " Preview — #{right_id} "
      draw_title(@right_frame, right_title)
    end

    # Draw a title into a frame (top border area).
    # @param [Curses::Window] frame
    # @param [String] label
    # @return [void]
    def draw_title(frame, label)
      width = frame.maxx
      text = label[0, [width - 4, 0].max]
      frame.setpos(0, 2)
      frame.addstr(' ' * [width - 4, 0].max)
      frame.setpos(0, 2)
      frame.addstr(text)
      frame.refresh
    end

    # Bold the focused frame’s title.
    # @return [void]
    def draw_focus
      update_titles
      if @focus == :left
        @left_frame.setpos(0, 2)
        @left_frame.attron(Curses::A_BOLD) { @left_frame.addstr('') }
      else
        @right_frame.setpos(0, 2)
        @right_frame.attron(Curses::A_BOLD) { @right_frame.addstr('') }
      end
      @left_frame.refresh
      @right_frame.refresh
    end

    # Help texts for the help bars.
    # @return [String]
    def left_help_text
      '↑/↓ j/k move • Space select • Tab focus • Enter generate • PgUp/PgDn • f fit • r refresh • z zebra • </> split'
    end

    # @return [String]
    def right_help_text
      '↑/↓ j/k scroll • PgUp/PgDn • g top • G bottom • Tab focus'
    end

    # Number of content rows (excluding help bar) on the left pane.
    # @return [Integer]
    def left_content_rows
      [@left_sub.maxy - 1, 0].max
    end

    # Number of content rows (excluding help bar) on the right pane.
    # @return [Integer]
    def right_content_rows
      [@right_sub.maxy - 1, 0].max
    end

    # Initialize color pairs and attributes for styling.
    # @return [void]
    def init_colors
      if Curses.has_colors?
        begin
          Curses.start_color
          Curses.use_default_colors if Curses.respond_to?(:use_default_colors)
        rescue StandardError
        end
        Curses.init_pair(CP_HELP, Curses::COLOR_CYAN, -1)
        Curses.init_pair(CP_HIGHLIGHT, Curses::COLOR_BLACK, Curses::COLOR_CYAN)
        Curses.init_pair(CP_SELECTED, Curses::COLOR_BLACK, Curses::COLOR_YELLOW)
        Curses.init_pair(CP_SEP, Curses::COLOR_BLUE, -1)
        Curses.init_pair(CP_ALT, Curses::COLOR_WHITE, -1)
      end

      if Curses.has_colors?
        @style_help      = Curses.color_pair(CP_HELP) | Curses::A_DIM
        @style_highlight = Curses.color_pair(CP_HIGHLIGHT)
        @style_selected  = Curses.color_pair(CP_SELECTED) | Curses::A_BOLD
        @style_sep       = Curses.color_pair(CP_SEP) | Curses::A_DIM
        @style_alt       = Curses.color_pair(CP_ALT) | Curses::A_DIM
      else
        @style_help      = Curses::A_DIM
        @style_highlight = Curses::A_STANDOUT
        @style_selected  = Curses::A_BOLD
        @style_sep       = Curses::A_DIM
        @style_alt       = Curses::A_DIM
      end
    end

    # Add a string with an attribute, guarding for zero attr.
    # @param [Curses::Window] win
    # @param [String] text
    # @param [Integer, nil] attr curses attribute (or nil)
    # @return [void]
    def addstr_with_attr(win, text, attr)
      if attr && attr != 0
        win.attron(attr)
        win.addstr(text)
        win.attroff(attr)
      else
        win.addstr(text)
      end
    end

    # Detect header lines in `git log --graph` output.
    # @param [Array<String>] lines
    # @return [Array<Integer>] indexes of header rows
    def detect_headers(lines)
      lines.each_index.select { |i| lines[i] =~ %r{^\s*[|\s\\/]*\*\s} }
    end

    # Map every line to a commit block index, and mark block boundaries.
    # @return [void]
    def recompute_blocks!
      @block_index_by_line = Array.new(@lines.length, 0)
      @boundary_set = Set.new
      @headers.each_with_index do |start, j|
        stop = @headers[j + 1] || @lines.length
        (start...stop).each { |idx| @block_index_by_line[idx] = j }
        @boundary_set << (stop - 1) if stop > start
      end
    end

    # Absolute line number of the currently selected commit header.
    # @return [Integer]
    def header_line_abs
      @headers[@selected_header_idx] || 0
    end

    # Extract an abbreviated SHA from a header line.
    # @param [Integer] abs_index
    # @return [String, nil] short or full SHA token
    def header_sha_at(abs_index)
      line = @lines[abs_index] || ''
      m = line.match(/\b([a-f0-9]{7,40})\b/i)
      m && m[1]
    end

    # Find current header index by a known SHA.
    # @param [String] sha
    # @return [Integer, nil]
    def find_header_index_by_sha(sha)
      return nil if sha.nil?

      @headers.find_index { |abs| (@lines[abs] || '').include?(sha[0, 7]) }
    end

    # Current commit block line range.
    # @return [Range]
    def current_commit_range
      start = header_line_abs
      stop  = @headers[@selected_header_idx + 1] || @lines.length
      (start...stop)
    end

    # Ensure the selected header (and optionally its block) is visible.
    # @param [Boolean] fit_full_block when true, keep the entire block inside viewport if it fits
    # @return [void]
    def ensure_visible(fit_full_block: @fit_full_block)
      rows = [left_content_rows, 1].max
      header_line = header_line_abs
      stop        = @headers[@selected_header_idx + 1] || @lines.length
      block_size  = stop - header_line

      if header_line < @offset
        @offset = header_line
      elsif header_line >= @offset + rows
        @offset = header_line - (rows - 1)
      end

      if fit_full_block && block_size <= rows
        @offset = stop - rows if stop > @offset + rows
        @offset = header_line if header_line < @offset
      end

      @offset = [[@offset, 0].max, [@lines.length - rows, 0].max].min
    end

    # Toggle selected mark on the current header.
    # @return [void]
    def toggle_selection
      idx = @selected_header_idx
      if @selected_header_idxs.include?(idx)
        @selected_header_idxs.delete(idx)
      else
        @selected_header_idxs << idx
        @selected_header_idxs.sort!
      end
    end

    # List selected SHAs in header order.
    # @return [Array<String>]
    def selected_shas_from_idxs
      @selected_header_idxs.map { |h_idx| header_sha_at(@headers[h_idx]) }.compact
    end

    # Render / update the live preview content.
    # @param [Boolean] reset_offset reset preview scroll to top
    # @return [void]
    def update_preview(reset_offset: false)
      anchors = selected_shas_from_idxs
      content =
        if anchors.size >= 2
          begin
            Changelogger::ChangelogGenerator.render(@commits, anchors)
          rescue StandardError => e
            "Preview error: #{e.message}"
          end
        else
          <<~TXT
            Preview — select at least 2 commits with SPACE to generate.
            Controls: #{right_help_text}
          TXT
        end

      @preview_lines = (content || '').split("\n")
      @preview_offset = 0 if reset_offset
      clamp_preview_offset
      redraw_right
    end

    # Clamp preview offset to visible range.
    # @return [void]
    def clamp_preview_offset
      max_off = [@preview_lines.length - right_content_rows, 0].max
      @preview_offset = [[@preview_offset, 0].max, max_off].min
    end

    # Refresh repo/graph/commits and preserve cursor and selections.
    # @return [void]
    def refresh_graph
      current_sha   = header_sha_at(header_line_abs)
      selected_shas = selected_shas_from_idxs

      @repo = Changelogger::Repo.info
      update_titles

      Graph.ensure!
      @lines   = Graph.build.split("\n")
      @headers = detect_headers(@lines)
      recompute_blocks!

      if current_sha
        new_idx = find_header_index_by_sha(current_sha)
        @selected_header_idx = new_idx || 0
      else
        @selected_header_idx = 0
      end

      @selected_header_idxs = selected_shas.filter_map { |sha| find_header_index_by_sha(sha) }.sort
      @commits = Changelogger::Git.commits

      ensure_visible
      redraw_left
      update_preview
    end

    # Resize split between panes.
    # @param [Integer] delta positive to expand left, negative to shrink
    # @return [void]
    def adjust_split(delta)
      new_left = compute_left_width(requested_left: @left_w + delta)
      return if new_left == @left_w

      @left_w = new_left
      setup_windows
      init_colors
      update_titles
      ensure_visible
      redraw
    end

    # Full redraw for both panes and focus indicator.
    # @return [void]
    def redraw
      redraw_left
      redraw_right
      draw_focus
    end

    # Redraw left pane (help bar + graph list with styling and separators).
    # @return [void]
    def redraw_left
      ensure_visible
      @left_sub.erase

      @left_sub.setpos(0, 0)
      help = left_help_text.ljust(@left_sub.maxx, ' ')[0, @left_sub.maxx]
      addstr_with_attr(@left_sub, help, @style_help)

      content_h = left_content_rows
      highlight = current_commit_range
      selected_header_abs = @selected_header_idxs.to_set { |i| @headers[i] }

      visible = @lines[@offset, content_h] || []
      visible.each_with_index do |line, i|
        idx = @offset + i
        @left_sub.setpos(i + 1, 0)

        text = line.ljust(@left_sub.maxx, ' ')[0, @left_sub.maxx]

        attr =
          if selected_header_abs.include?(idx)
            @style_selected
          elsif highlight.cover?(idx)
            @style_highlight
          elsif @zebra_blocks && @block_index_by_line[idx].to_i.odd?
            @style_alt
          end

        addstr_with_attr(@left_sub, text, attr)

        next unless @boundary_set.include?(idx)

        start_col = [line.rstrip.length, 0].max
        start_col = [[start_col, 0].max, @left_sub.maxx - 1].min
        sep_width = @left_sub.maxx - start_col
        next unless sep_width.positive?

        @left_sub.setpos(i + 1, start_col)
        pattern = '┄' * sep_width
        addstr_with_attr(@left_sub, pattern[0, sep_width], @style_sep)
      end

      (visible.length...content_h).each do |i|
        @left_sub.setpos(i + 1, 0)
        @left_sub.addstr(' ' * @left_sub.maxx)
      end

      @left_sub.refresh
    end

    # Redraw right pane (help bar + markdown preview).
    # @return [void]
    def redraw_right
      @right_sub.erase

      @right_sub.setpos(0, 0)
      help = right_help_text.ljust(@right_sub.maxx, ' ')[0, @right_sub.maxx]
      addstr_with_attr(@right_sub, help, @style_help)

      content_h = right_content_rows
      clamp_preview_offset
      visible = @preview_lines[@preview_offset, content_h] || []
      visible.each_with_index do |line, i|
        @right_sub.setpos(i + 1, 0)
        @right_sub.addstr(line.ljust(@right_sub.maxx, ' ')[0, @right_sub.maxx])
      end

      (visible.length...content_h).each do |i|
        @right_sub.setpos(i + 1, 0)
        @right_sub.addstr(' ' * @right_sub.maxx)
      end

      @right_sub.refresh
    end

    # Show a transient message at the bottom of a window.
    # @param [Curses::Window] win
    # @param [String] msg
    # @return [void]
    def flash_message(win, msg)
      return if win.maxy <= 0 || win.maxx <= 0

      win.setpos(win.maxy - 1, 0)
      txt = msg.ljust(win.maxx, ' ')[0, win.maxx]
      win.attron(Curses::A_BOLD)
      win.addstr(txt)
      win.attroff(Curses::A_BOLD)
      win.refresh
      sleep(0.6)
      redraw
    end

    # Safely fetch a Curses key constant.
    # @param [Symbol] name
    # @return [Integer, nil]
    def key_const(name)
      Curses::Key.const_get(name)
    rescue NameError
      nil
    end

    # Normalize raw key codes into symbols we can switch on.
    # @param [Object] ch raw key
    # @return [Symbol] normalized key
    def normalize_key(ch)
      return :none if ch.nil?

      return :tab       if ch == "\t" || ch == 9 || ((kc = key_const(:TAB)) && ch == kc)
      return :shift_tab if (kc = key_const(:BTAB)) && ch == kc
      return :quit if ['q', 27].include?(ch)

      enter_key = key_const(:ENTER)
      return :enter if ch == "\r" || ch == "\n" || ch == 10 || ch == 13 || (enter_key && ch == enter_key)

      return :up        if ch == key_const(:UP) || ch == 'k'
      return :down      if ch == key_const(:DOWN) || ch == 'j'
      return :page_up   if ch == key_const(:PPAGE)
      return :page_down if ch == key_const(:NPAGE)

      return :toggle  if ch == ' '
      return :fit     if ch == 'f'
      return :refresh if ch == 'r'
      return :zebra   if ch == 'z'
      return :g       if ch == 'g'
      return :G       if ch == 'G'
      return :lt      if ch == '<'
      return :gt      if ch == '>'

      :other
    end

    # The main input loop (handles focus, navigation, selection, actions).
    # @return [void]
    def handle_keyboard_input
      loop do
        raw = (@focus == :left ? @left_sub.getch : @right_sub.getch)
        key = normalize_key(raw)

        case key
        when :tab, :shift_tab
          @focus = (@focus == :left ? :right : :left)
          draw_focus
        when :quit
          @cancelled = true
          break
        when :enter
          shas = selected_shas_from_idxs
          if shas.size >= 2
            @selected_shas = shas
            break
          else
            flash_message(@left_sub, 'Select at least 2 commits (space)')
          end
        when :lt
          adjust_split(-4)
        when :gt
          adjust_split(+4)
        when :up
          if @focus == :left
            if @selected_header_idx.positive?
              @selected_header_idx -= 1
              ensure_visible
              redraw_left
              update_preview
            end
          else
            @preview_offset -= 1
            redraw_right
          end
        when :down
          if @focus == :left
            if @selected_header_idx < @headers.length - 1
              @selected_header_idx += 1
              ensure_visible
              redraw_left
              update_preview
            end
          else
            @preview_offset += 1
            redraw_right
          end
        when :page_up
          if @focus == :left
            @selected_header_idx = [@selected_header_idx - 5, 0].max
            ensure_visible
            redraw_left
            update_preview
          else
            @preview_offset -= right_content_rows
            redraw_right
          end
        when :page_down
          if @focus == :left
            @selected_header_idx = [@selected_header_idx + 5, @headers.length - 1].min
            ensure_visible
            redraw_left
            update_preview
          else
            @preview_offset += right_content_rows
            redraw_right
          end
        when :g
          if @focus == :right
            @preview_offset = 0
            redraw_right
          end
        when :G
          if @focus == :right
            @preview_offset = [@preview_lines.length - right_content_rows, 0].max
            redraw_right
          end
        when :toggle
          if @focus == :left
            toggle_selection
            redraw_left
            update_preview(reset_offset: true)
          end
        when :fit
          if @focus == :left
            @fit_full_block = !@fit_full_block
            ensure_visible
            redraw_left
          end
        when :zebra
          if @focus == :left
            @zebra_blocks = !@zebra_blocks
            redraw_left
          end
        when :refresh
          refresh_graph
        end
      end
    end
  end
end
