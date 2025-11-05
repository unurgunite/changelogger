# frozen_string_literal: true

module Changelogger
  Commit = Struct.new(:sha, :short, :date, :subject, :body, keyword_init: true)

  class Git
    SEP = "\x01"

    def self.commits
      format = "%H#{SEP}%h#{SEP}%ad#{SEP}%s#{SEP}%b"
      cmd = "git log --date=short --reverse --pretty=format:'#{format}'"
      out = `#{cmd}`
      out.split("\n").map do |line|
        sha, short, date, subject, body = line.split(SEP, 5)
        Commit.new(
          sha: sha,
          short: short,
          date: date,
          subject: (subject || "").strip,
          body: (body || "").strip
        )
      end
    end
  end
end
