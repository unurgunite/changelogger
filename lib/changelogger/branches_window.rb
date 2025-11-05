# frozen_string_literal: true

require "set"
require "curses"
require_relative "git"
require_relative "versioner"
require_relative "changelog_generator"
require_relative "repo_info"

module Changelogger
  # Renders and caches `git log --graph` into a file, auto-regenerating as needed.
  class Graph
    class << self
      FILENAME = ".graph"

      def ensure!
        content = `git log --graph --decorate=short --date=short --pretty=format:'%h %d %s' 2>/dev/null`
        if content.nil? || content.strip.empty?
          content = "(no git graph available — empty repo or not a git repository)\n"
        end
        File.open(FILENAME, "w") { |f| f.write(content) }
      rescue StandardError => e
        File.open(FILENAME, "w") { |f| f.write("(error generating graph: #{e.message})\n") }
      end

      def width
        ensure! unless File.exist?(FILENAME)
        ensure!
        max = 1
        IO.foreach(FILENAME) { |line| max = [max, line.rstrip.length].max }
        max
      end

      def build
        ensure! unless File.exist?(FILENAME)
        File.read(FILENAME)
      end
    end
  end

  # Left-right split with live preview on the right
  class BranchWindow
    attr_reader :selected_shas

    CP_HELP      = 2
    CP_HIGHLIGHT = 3  # current cursor commit block
    CP_SELECTED  = 4  # selected anchor commit header
    CP_SEP       = 5  # thin separators
    CP_ALT       = 6  # zebra alt shading

    def initialize(max_height: 50, top: 1, left: 0, left_width: nil)
      @top   = top
      @left  = left
      @width = Curses.cols - @left
      screen_height = Curses.lines
      @height = [screen_height - @top, max_height].min

      @repo = Changelogger::Repo.info

      # Load graph and compute preferred left width
      @lines = Graph.build.split("\n")
      preferred_left = Graph.width + 4
      @left_min  = 24
      @right_min = 28
      @left_w = compute_left_width(requested_left: left_width || preferred_left)

      # Left pane (graph) state
      @headers = detect_headers(@lines)
      @selected_header_idx  = 0
      @selected_header_idxs = [] # indices into @headers array
      @offset          = 0
      @fit_full_block  = true
      @zebra_blocks    = true

      # Precompute block mapping and boundaries for separators/zebra
      recompute_blocks!

      # Right pane (preview) state
      @commits = Changelogger::Git.commits # oldest -> newest
      @preview_lines  = []
      @preview_offset = 0

      @focus = :left # :left or :right
      @cancelled = false

      setup_windows
      init_colors
      update_titles
      update_preview(reset_offset: true)
      ensure_visible
      redraw
    end

    def select_commits
      handle_keyboard_input
      @cancelled ? nil : (@selected_shas || [])
    ensure
      teardown
    end

    private

    # ---------- Layout / windows ----------

    def compute_left_width(requested_left:)
      w = @width
      lw = requested_left.to_i
      [[lw, @left_min].max, w - @right_min].min
    end

    def setup_windows
      destroy_windows

      # LEFT FRAME
      @left_frame = Curses::Window.new(@height, @left_w, @top, @left)
      @left_frame.box

      @left_sub = @left_frame.subwin(@height - 2, @left_w - 2, @top + 1, @left + 1)
      @left_sub.keypad(true)
      @left_sub.scrollok(false)

      # RIGHT FRAME
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

    def destroy_windows
      @left_sub&.close
      @left_frame&.close
      @right_sub&.close
      @right_frame&.close
    rescue StandardError
      # ignore
    end

    def teardown
      destroy_windows
      Curses.close_screen
    rescue StandardError
      # ignore
    end

    def update_titles
      # Build left title: repo name [branch@sha*]
      dirty = @repo.dirty ? "*" : ""
      left_title = " Graph — #{@repo.name} [#{@repo.branch}@#{@repo.head_short}#{dirty}] "
      draw_title(@left_frame, left_title)

      # Build right title: remote slug or path
      right_id = @repo.remote_slug || @repo.name
      right_title = " Preview — #{right_id} "
      draw_title(@right_frame, right_title)
    end

    def draw_title(frame, label)
      width = frame.maxx
      text = label[0, [width - 4, 0].max] # keep margins
      frame.setpos(0, 2)
      frame.addstr(" " * [width - 4, 0].max) # clear previous
      frame.setpos(0, 2)
      frame.addstr(text)
      frame.refresh
    end

    def draw_focus
      # Bold the current frame title text
      lf = @left_frame
      rf = @right_frame

      # Re-draw to ensure we keep titles, then bold the focused one
      update_titles

      if @focus == :left
        lf.setpos(0, 2)
        lf.attron(Curses::A_BOLD) { lf.addstr(line_at(lf)) }
      else
        rf.setpos(0, 2)
        rf.attron(Curses::A_BOLD) { rf.addstr(line_at(rf)) }
      end
      lf.refresh
      rf.refresh
    end

    def line_at(frame)
      frame.maxx
      frame.setpos(0, 2)
      # There is no direct read; we just re-truncate label logic for simplicity.
      # draw_focus calls update_titles first, so titles are already set.
      ""
    end

    # Help bars
    def left_help_text
      "↑/↓ j/k move • Space select • Tab focus • Enter generate • PgUp/PgDn • f fit • r refresh • z zebra • </> split"
    end

    def right_help_text
      "↑/↓ j/k scroll • PgUp/PgDn • g top • G bottom • Tab focus"
    end

    def left_content_rows
      [@left_sub.maxy - 1, 0].max
    end

    def right_content_rows
      [@right_sub.maxy - 1, 0].max
    end

    # ---------- Colors ----------

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

    def addstr_with_attr(win, text, attr)
      if attr && attr != 0
        win.attron(attr)
        win.addstr(text)
        win.attroff(attr)
      else
        win.addstr(text)
      end
    end

    # ---------- Graph parsing / selection ----------

    def detect_headers(lines)
      lines.each_index.select { |i| lines[i] =~ %r{^\s*[|\s\\/]*\*\s} }
    end

    def recompute_blocks!
      @block_index_by_line = Array.new(@lines.length, 0)
      @boundary_set = Set.new
      @headers.each_with_index do |start, j|
        stop = @headers[j + 1] || @lines.length
        (start...stop).each { |idx| @block_index_by_line[idx] = j }
        @boundary_set << (stop - 1) if stop > start # last row of this block
      end
    end

    def header_line_abs
      @headers[@selected_header_idx] || 0
    end

    def header_sha_at(abs_index)
      line = @lines[abs_index] || ""
      m = line.match(/\b([a-f0-9]{7,40})\b/i)
      m && m[1]
    end

    def find_header_index_by_sha(sha)
      return nil if sha.nil?

      @headers.find_index { |abs| (@lines[abs] || "").include?(sha[0, 7]) }
    end

    def current_commit_range
      start = header_line_abs
      stop  = @headers[@selected_header_idx + 1] || @lines.length
      (start...stop)
    end

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

    # ---------- Preview ----------

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

      @preview_lines = (content || "").split("\n")
      @preview_offset = 0 if reset_offset
      clamp_preview_offset
      redraw_right
    end

    def clamp_preview_offset
      max_off = [@preview_lines.length - right_content_rows, 0].max
      @preview_offset = [[@preview_offset, 0].max, max_off].min
    end

    # ---------- Actions ----------

    def refresh_graph
      current_sha   = header_sha_at(header_line_abs)
      selected_shas = selected_shas_from_idxs

      # refresh repo info and titles
      @repo = Changelogger::Repo.info
      update_titles

      Graph.ensure!
      @lines   = Graph.build.split("\n")
      @headers = detect_headers(@lines)
      recompute_blocks!

      # restore current cursor position by SHA
      if current_sha
        new_idx = find_header_index_by_sha(current_sha)
        @selected_header_idx = new_idx || 0
      else
        @selected_header_idx = 0
      end

      # restore selected marks by SHA
      @selected_header_idxs = selected_shas.filter_map { |sha| find_header_index_by_sha(sha) }.sort

      # refresh commits list too (in case repo changed)
      @commits = Changelogger::Git.commits

      ensure_visible
      redraw_left
      update_preview # keep preview scroll
    end

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

    # ---------- Rendering ----------

    def redraw
      redraw_left
      redraw_right
      draw_focus
    end

    def redraw_left
      ensure_visible
      @left_sub.erase

      # Help bar (row 0)
      @left_sub.setpos(0, 0)
      help = left_help_text.ljust(@left_sub.maxx, " ")[0, @left_sub.maxx]
      addstr_with_attr(@left_sub, help, @style_help)

      # Content rows start at 1
      content_h = left_content_rows
      highlight = current_commit_range
      selected_header_abs = @selected_header_idxs.map { |i| @headers[i] }.to_set

      visible = @lines[@offset, content_h] || []
      visible.each_with_index do |line, i|
        idx = @offset + i
        @left_sub.setpos(i + 1, 0)

        text = line.ljust(@left_sub.maxx, " ")[0, @left_sub.maxx]

        # Determine attributes
        attr =
          if selected_header_abs.include?(idx)
            @style_selected
          elsif highlight.cover?(idx)
            @style_highlight
          elsif @zebra_blocks && @block_index_by_line[idx].to_i.odd?
            @style_alt
          end

        addstr_with_attr(@left_sub, text, attr)

        # Thin broken separator at commit boundary (in the trailing margin only)
        next unless @boundary_set.include?(idx)

        # Start drawing dashes after the end of visible content to avoid overwriting the graph
        start_col = [line.rstrip.length, 0].max
        start_col = [[start_col, 0].max, @left_sub.maxx - 1].min
        sep_width = @left_sub.maxx - start_col
        next unless sep_width.positive?

        @left_sub.setpos(i + 1, start_col)
        pattern = "┄" * sep_width # falls back fine if font lacks the glyph
        addstr_with_attr(@left_sub, pattern[0, sep_width], @style_sep)
      end

      # Clear tail
      (visible.length...content_h).each do |i|
        @left_sub.setpos(i + 1, 0)
        @left_sub.addstr(" " * @left_sub.maxx)
      end

      @left_sub.refresh
    end

    def redraw_right
      @right_sub.erase

      # Help bar (row 0)
      @right_sub.setpos(0, 0)
      help = right_help_text.ljust(@right_sub.maxx, " ")[0, @right_sub.maxx]
      addstr_with_attr(@right_sub, help, @style_help)

      # Content rows start at 1
      content_h = right_content_rows
      clamp_preview_offset
      visible = @preview_lines[@preview_offset, content_h] || []
      visible.each_with_index do |line, i|
        @right_sub.setpos(i + 1, 0)
        @right_sub.addstr(line.ljust(@right_sub.maxx, " ")[0, @right_sub.maxx])
      end

      (visible.length...content_h).each do |i|
        @right_sub.setpos(i + 1, 0)
        @right_sub.addstr(" " * @right_sub.maxx)
      end

      @right_sub.refresh
    end

    def flash_message(win, msg)
      return if win.maxy <= 0 || win.maxx <= 0

      win.setpos(win.maxy - 1, 0)
      txt = msg.ljust(win.maxx, " ")[0, win.maxx]
      win.attron(Curses::A_BOLD)
      win.addstr(txt)
      win.attroff(Curses::A_BOLD)
      win.refresh
      sleep(0.6)
      redraw
    end

    # ---------- Input ----------

    def key_const(name)
      Curses::Key.const_get(name)
    rescue NameError
      nil
    end

    def normalize_key(ch)
      return :none if ch.nil?

      # Focus switching
      return :tab       if ch == "\t" || ch == 9 || (kc = key_const(:TAB)) && ch == kc
      return :shift_tab if (kc = key_const(:BTAB)) && ch == kc

      # Quit / enter
      return :quit if ["q", 27].include?(ch)

      enter_key = key_const(:ENTER)
      return :enter if ch == "\r" || ch == "\n" || ch == 10 || ch == 13 || (enter_key && ch == enter_key)

      # Navigation
      return :up        if ch == key_const(:UP) || ch == "k"
      return :down      if ch == key_const(:DOWN) || ch == "j"
      return :page_up   if ch == key_const(:PPAGE)
      return :page_down if ch == key_const(:NPAGE)

      # Actions
      return :toggle  if ch == " "
      return :fit     if ch == "f"
      return :refresh if ch == "r"
      return :zebra   if ch == "z"
      return :g       if ch == "g"
      return :G       if ch == "G"
      return :lt      if ch == "<"
      return :gt      if ch == ">"

      :other
    end

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
            flash_message(@left_sub, "Select at least 2 commits (space)")
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
