# frozen_string_literal: false

require "curses"
require_relative "header"
require_relative "branches_window"


Curses.init_screen
Curses.curs_set(0)

Changelogger::Header.standard_header

Changelogger::BranchWindow.new

