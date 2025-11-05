# frozen_string_literal: true

module Changelogger
  RepoInfo = Struct.new(:name, :path, :branch, :head_short, :remote, :remote_slug, :dirty, keyword_init: true)

  class Repo
    class << self
      def info
        path = cmd("git rev-parse --show-toplevel").strip
        name = path.empty? ? File.basename(Dir.pwd) : File.basename(path)
        branch = cmd("git rev-parse --abbrev-ref HEAD").strip
        branch = "(detached)" if branch.empty? || branch == "HEAD"
        head_short = cmd("git rev-parse --short HEAD").strip
        remote = cmd("git config --get remote.origin.url").strip
        dirty = !cmd("git status --porcelain").strip.empty?

        RepoInfo.new(
          name: name,
          path: path.empty? ? Dir.pwd : path,
          branch: branch,
          head_short: head_short,
          remote: remote,
          remote_slug: to_slug(remote),
          dirty: dirty
        )
      end

      private

      def cmd(s)
        `#{s} 2>/dev/null`
      rescue StandardError
        ""
      end

      def to_slug(url)
        return nil if url.to_s.empty?

        if url =~ %r{\Agit@github\.com:([\w.-]+/[\w.-]+)(?:\.git)?\z}i
          Regexp.last_match(1)
        elsif url =~ %r{\Ahttps?://(?:www\.)?github\.com/([\w.-]+/[\w.-]+)(?:\.git)?\z}i
          Regexp.last_match(1)
        end
      end
    end
  end
end
