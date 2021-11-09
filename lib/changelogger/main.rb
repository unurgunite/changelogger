# frozen_string_literal: false

require "curses"
require_relative "header"

Curses.init_screen
Curses.curs_set(0)

Changelogger::Header.standard_header

#branches_win = Curses::Window.new(Curses.lines / 2 - 1, Curses.cols / 2 - 1, 0, 0)
