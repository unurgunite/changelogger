# frozen_string_literal: false

require "curses"
require_relative "header"
require_relative "branches_window"
require_relative "git"
require_relative "versioner"
require_relative "changelog_generator"
require_relative "preview_window"

Curses.init_screen
Curses.cbreak      # <= add this
Curses.curs_set(0)
Curses.noecho

Changelogger::Header.new

win = Changelogger::BranchWindow.new
selected = win.select_commits # closes screen on exit

if selected.nil?
  # user cancelled with q/ESC — exit quietly (or puts "Cancelled." if you prefer)
elsif selected.size >= 2
  commits = Changelogger::Git.commits
  path = Changelogger::ChangelogGenerator.generate(commits, selected, path: "CHANGELOG.md")
  puts "Wrote #{path} ✅"
else
  puts "No CHANGELOG generated (need at least 2 commits)."
end
