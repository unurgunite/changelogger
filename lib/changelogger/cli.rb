# frozen_string_literal: true

require 'optparse'
require 'tmpdir'
require 'fileutils'

require_relative 'version'
require_relative 'git'
require_relative 'changelog_generator'

module Changelogger
  # +Changelogger::CLI+ provides both TUI and non-interactive CLI entrypoints.
  class CLI
    # +Changelogger::CLI.start+                     -> Integer
    #
    # Parses CLI arguments and runs either interactive TUI or headless generation.
    # Returns an exit code (0 on success).
    #
    # @param [Array<String>] argv command line arguments (default: ARGV)
    # @return [Integer] exit status code
    def self.start(argv = ARGV)
      new.start(argv)
    end

    # +Changelogger::CLI#start+                     -> Integer
    #
    # @param [Array<String>] argv
    # @return [Integer] exit code
    def start(argv)
      mode         = :tui
      anchors      = []
      output       = 'CHANGELOG.md'
      dry_run      = false
      major        = 0
      minor_start  = 1
      base_patch   = 10

      parser = OptionParser.new do |o|
        o.banner = 'Usage: changelogger [options] [REPO]'
        o.separator ''
        o.separator 'REPO can be:'
        o.separator '  - local path (/path/to/repo)'
        o.separator '  - GitHub slug (owner/repo)'
        o.separator '  - git URL (https://... or git@...)'
        o.separator ''
        o.on('-g', '--generate', 'Non-interactive: generate CHANGELOG from anchors') { mode = :generate }
        o.on('-a', '--anchors x,y,z', Array, 'Anchors (SHA/tag/branch), 2+ required in chronological order') do |v|
          anchors = v || []
        end
        o.on('-o', '--output PATH', 'Output file (default: CHANGELOG.md)') { |v| output = v }
        o.on('--major N', Integer, 'Major version (default: 0)') { |v| major = v }
        o.on('--minor-start N', Integer, 'Minor start index (default: 1)') { |v| minor_start = v }
        o.on('--base-patch N', Integer, 'Patch spacing base (default: 10)') { |v| base_patch = v }
        o.on('--dry-run', 'Print to stdout (do not write file)') { dry_run = true }
        o.on('--tui', 'Force interactive TUI (default if no --generate)') { mode = :tui }
        o.on('-v', '--version', 'Print version') do
          puts Changelogger::VERSION
          return 0
        end
        o.on('-h', '--help', 'Show help') do
          puts o
          return 0
        end
      end

      repo_spec = nil
      begin
        parser.order!(argv) { |arg| repo_spec ||= arg }
      rescue OptionParser::ParseError => e
        warn e.message
        warn parser
        return 2
      end

      with_repo(repo_spec) do
        case mode
        when :generate
          return run_generate(anchors, output, dry_run, major, minor_start, base_patch)
        else
          return run_tui(output, major, minor_start, base_patch)
        end
      end
    end

    private

    # +Changelogger::CLI#run_tui+                   -> Integer
    #
    # Launches TUI and writes the CHANGELOG if the user selected 2+ anchors.
    # @param [String] output output path
    # @param [Integer] major
    # @param [Integer] minor_start
    # @param [Integer] base_patch
    # @return [Integer] exit code
    def run_tui(output, major, minor_start, base_patch)
      require_relative 'tui'
      selected = Changelogger::TUI.run
      return 0 if selected.nil? # cancelled

      if selected.size >= 2
        commits = Changelogger::Git.commits
        path = Changelogger::ChangelogGenerator.generate(
          commits,
          selected,
          path: output,
          major: major,
          minor_start: minor_start,
          base_patch: base_patch
        )
        puts "Wrote #{path} ✅"
        0
      else
        puts 'No CHANGELOG generated (need at least 2 commits).'
        1
      end
    end

    # +Changelogger::CLI#run_generate+              -> Integer
    #
    # Headless mode: resolves anchors, renders or writes the CHANGELOG.
    # @param [Array<String>] anchor_tokens tokens (sha/tag/branch)
    # @param [String] output path
    # @param [Boolean] dry_run if true, print to stdout
    # @param [Integer] major
    # @param [Integer] minor_start
    # @param [Integer] base_patch
    # @return [Integer] exit code
    def run_generate(anchor_tokens, output, dry_run, major, minor_start, base_patch)
      if anchor_tokens.size < 2
        warn 'Error: --generate requires at least 2 --anchors (SHA/tag/branch).'
        return 2
      end

      resolved = anchor_tokens.filter_map { |t| resolve_commit(t) }
      if resolved.size < 2
        warn "Error: could not resolve at least two anchors: #{anchor_tokens.inspect}"
        return 2
      end

      commits = Changelogger::Git.commits
      if dry_run
        puts Changelogger::ChangelogGenerator.render(
          commits,
          resolved,
          major: major,
          minor_start: minor_start,
          base_patch: base_patch
        )
      else
        path = Changelogger::ChangelogGenerator.generate(
          commits,
          resolved,
          path: output,
          major: major,
          minor_start: minor_start,
          base_patch: base_patch
        )
        puts "Wrote #{path} ✅"
      end
      0
    end

    # ---------- repo resolution ----------

    # +Changelogger::CLI#with_repo+                 -> Integer
    #
    # Changes directory into a target repo (path/slug/url) for the duration of the block.
    # Clones remotes into a temporary directory and cleans it up afterwards.
    #
    # @param [String, nil] repo_spec path, GitHub slug (owner/repo), or git URL
    # @yield [] block to execute inside the repo
    # @return [Integer] 0
    def with_repo(repo_spec)
      orig_dir = Dir.pwd
      tmp_dir = nil

      if repo_spec && !repo_spec.empty?
        if File.directory?(repo_spec)
          Dir.chdir(File.expand_path(repo_spec))
          unless inside_git_repo?
            warn "#{repo_spec.inspect} is not a git repository. Continuing, but output may be empty."
          end
        else
          url = looks_like_url?(repo_spec) ? repo_spec : github_slug_to_url(repo_spec)
          if url
            tmp_dir = Dir.mktmpdir('changelogger-')
            clone_ok = system('git', 'clone', '--no-checkout', '--filter=blob:none', '--depth=1000', url, tmp_dir,
                              out: File::NULL, err: File::NULL)
            clone_ok ||= system('git', 'clone', url, tmp_dir)
            if clone_ok
              Dir.chdir(tmp_dir)
            else
              warn "Failed to clone #{url}. Running in current directory."
            end
          else
            warn "Unrecognized repo argument: #{repo_spec.inspect}. Expected a directory, " \
                 'GitHub slug (owner/repo), or git URL.'
          end
        end
      end

      yield
      0
    ensure
      begin
        Dir.chdir(orig_dir)
      rescue StandardError
        nil
      end
      FileUtils.remove_entry(tmp_dir) if tmp_dir && File.directory?(tmp_dir)
    end

    # +Changelogger::CLI#inside_git_repo?+          -> Bool
    # @return [Bool] true if inside a git work tree
    def inside_git_repo?
      system('git', 'rev-parse', '--is-inside-work-tree', out: File::NULL, err: File::NULL)
    end

    # +Changelogger::CLI#looks_like_url?+           -> Bool
    # @param [String] s
    # @return [Bool]
    def looks_like_url?(s)
      s =~ %r{\Ahttps?://} || s.start_with?('git@')
    end

    # +Changelogger::CLI#github_slug_to_url+        -> String, nil
    # Converts "owner/repo" or "github.com/owner/repo" into an https URL.
    # @param [String] s
    # @return [String, nil]
    def github_slug_to_url(s)
      if s =~ %r{\Ahttps?://(?:www\.)?github\.com/([\w.-]+/[\w.-]+)(?:\.git)?\z}i
        "https://github.com/#{::Regexp.last_match(1)}.git"
      elsif s =~ %r{\A(?:github\.com/)?([\w.-]+/[\w.-]+)(?:\.git)?\z}i
        "https://github.com/#{::Regexp.last_match(1)}.git"
      end
    end

    # +Changelogger::CLI#resolve_commit+            -> String, nil
    #
    # Resolves a token (sha/tag/branch) to a 40-char commit SHA.
    # @param [String] token
    # @return [String, nil]
    def resolve_commit(token)
      full = `git rev-parse -q --verify #{token}^{commit} 2>/dev/null`.strip
      $CHILD_STATUS.success? && full.match?(/\A[0-9a-f]{40}\z/i) ? full : nil
    end
  end
end
