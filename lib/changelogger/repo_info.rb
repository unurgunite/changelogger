# frozen_string_literal: true

module Changelogger
  # +Changelogger::RepoInfo+ holds metadata about the current repository.
  #
  # @!attribute [rw] name
  #   @return [String] repo name (directory name)
  # @!attribute [rw] path
  #   @return [String] absolute repo root path
  # @!attribute [rw] branch
  #   @return [String] HEAD branch or "(detached)"
  # @!attribute [rw] head_short
  #   @return [String] abbreviated HEAD sha
  # @!attribute [rw] remote
  #   @return [String] remote.origin.url (may be empty)
  # @!attribute [rw] remote_slug
  #   @return [String, nil] "owner/repo" for GitHub remotes, otherwise nil
  # @!attribute [rw] dirty
  #   @return [Boolean] true if there are uncommitted changes
  RepoInfo = Struct.new(:name, :path, :branch, :head_short, :remote, :remote_slug, :dirty, keyword_init: true)

  # +Changelogger::Repo+ reads basic repository info for display.
  class Repo
    class << self
      # +Changelogger::Repo.info+                      -> Changelogger::RepoInfo
      #
      # Reads repo root, branch, HEAD short sha, origin url, and dirty flag.
      # @return [RepoInfo]
      def info
        path = cmd('git rev-parse --show-toplevel').strip
        name = path.empty? ? File.basename(Dir.pwd) : File.basename(path)
        branch = cmd('git rev-parse --abbrev-ref HEAD').strip
        branch = '(detached)' if branch.empty? || branch == 'HEAD'
        head_short = cmd('git rev-parse --short HEAD').strip
        remote = cmd('git config --get remote.origin.url').strip
        dirty = !cmd('git status --porcelain').strip.empty?

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

      # +Changelogger::Repo.cmd+                        -> String
      # @private
      # Runs a shell command and returns its stdout (or empty string on error).
      # @param [String] s shell command
      # @return [String]
      def cmd(s)
        `#{s} 2>/dev/null`
      rescue StandardError
        ''
      end

      # +Changelogger::Repo.to_slug+                    -> String, nil
      # @private
      # Extracts owner/repo from GitHub remotes or returns nil for others.
      # @param [String] url git remote URL
      # @return [String, nil]
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
