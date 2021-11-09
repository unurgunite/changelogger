module Changelogger
  class BranchWindow
    def initialize
      branches
    end

    def branches
       #branches_win = Curses::Window.new(Curses.lines / 2 - 1, Curses.cols / 2 - 1, 0, 0)
      win2 = Curses::Window.new(Curses.lines / 2 - 1, Curses.cols / 2 - 1,
                            Curses.lines / 2, Curses.cols / 2)
      win2.box("|", "-")
      win2.refresh
      2.upto(win2.maxx - 3) do |i|
        win2.setpos(win2.maxy / 2, i)
        win2 << "*"
        win2.refresh
        sleep 0.05
      end
    end
  end
end

