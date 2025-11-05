# frozen_string_literal: true

module Changelogger
  # Changelog generator.
  class ChangelogGenerator
    class << self
      # +Changelogger::ChangelogGenerator.build_sections+                      -> String
      #
      # Build sections from versioned commits.
      #
      # @param [Array<(Integer, Changelogger::Commit, String)>] versioned
      # @return [String]
      def build_sections(versioned)
        versioned.map do |(_i, c, v)|
          lines = []
          lines << "## [#{v}] - #{c.date}"
          lines << ''
          lines << "- #{c.subject} (#{c.short})"
          c.body.split("\n").each { |b| lines << "  #{b}" } unless c.body.nil? || c.body.empty?
          lines << ''
          lines.join("\n")
        end.join("\n")
      end

      # +Changelogger::ChangelogGenerator.render+                              -> String
      #
      # Render the changelog content.
      #
      # @param [Array<Changelogger::Commit>] commits
      # @param [Array<String>] anchor_shas
      # @param [Integer] major
      # @param [Integer] minor_start
      # @param [Integer] base_patch
      # @return [String]
      def render(commits, anchor_shas, major: 0, minor_start: 1, base_patch: 10)
        sha_to_idx = commits.map(&:sha)
        short_to_idx = commits.map(&:short)

        anchor_indices = anchor_shas.filter_map do |sha|
          full_idx = sha_to_idx.index(sha)
          full_idx || short_to_idx.index(sha[0, 7])
        end
        raise 'Need at least 2 valid commits selected' if anchor_indices.size < 2

        versioned = Versioner.assign(commits, anchor_indices, major: major, minor_start: minor_start,
                                                              base_patch: base_patch)
        header = "## [Unreleased]\n\n"
        sections = build_sections(versioned)
        [header, sections].join("\n")
      end

      # +Changelogger::ChangelogGenerator.generate+                            -> String
      #
      # Generate the changelog file.
      #
      # @param [Array<Changelogger::Commit>] commits
      # @param [Array<String>] anchor_shas
      # @param [String] path
      # @param [Integer] major
      # @param [Integer] minor_start
      # @param [Integer] base_patch
      # @return [String] path
      def generate(commits, anchor_shas, path: 'CHANGELOG.md', major: 0, minor_start: 1, base_patch: 10)
        content = render(commits, anchor_shas, major: major, minor_start: minor_start, base_patch: base_patch)
        File.write(path, content)
        path
      end
    end
  end
end
