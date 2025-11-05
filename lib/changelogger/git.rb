# frozen_string_literal: true

module Changelogger
  # +Changelogger::Commit+ is a plain struct representing a git commit.
  #
  # @!attribute [rw] sha
  #   @return [String] Full 40-char SHA
  # @!attribute [rw] short
  #   @return [String] Abbreviated SHA
  # @!attribute [rw] date
  #   @return [String] Commit date (YYYY-MM-DD)
  # @!attribute [rw] subject
  #   @return [String] First line message
  # @!attribute [rw] body
  #   @return [String] Remaining message body (could be empty)
  Commit = Struct.new(:sha, :short, :date, :subject, :body, keyword_init: true)

  # +Changelogger::Git+ wraps read-only git queries used by this gem.
  class Git
    # Separator used for pretty-format parsing
    SEP = "\x01"

    # +Changelogger::Git.commits+                     -> Array<Changelogger::Commit>
    #
    # Returns repository commits in chronological order (oldest-first).
    # Uses: git log --date=short --reverse --pretty=format:'...'
    #
    # @return [Array<Commit>]
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
          subject: (subject || '').strip,
          body: (body || '').strip
        )
      end
    end
  end
end
