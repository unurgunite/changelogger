# frozen_string_literal: true

module Changelogger
  class ChangelogGenerator
    class << self
      def build_sections(versioned)
        versioned.map do |(_i, c, v)|
          lines = []
          lines << "## [#{v}] - #{c.date}"
          lines << ""
          lines << "- #{c.subject} (#{c.short})"
          c.body.split("\n").each { |b| lines << "  #{b}" } unless c.body.nil? || c.body.empty?
          lines << ""
          lines.join("\n")
        end.join("\n")
      end

      def render(commits, anchor_shas)
        sha_to_idx = commits.map(&:sha)
        short_to_idx = commits.map(&:short)

        anchor_indices = anchor_shas.filter_map do |sha|
          full_idx = sha_to_idx.index(sha)
          full_idx || short_to_idx.index(sha[0, 7])
        end

        raise "Need at least 2 valid commits selected" if anchor_indices.size < 2

        versioned = Versioner.assign(commits, anchor_indices)
        header = "## [Unreleased]\n\n"
        sections = build_sections(versioned)
        [header, sections].join("\n")
      end

      def generate(commits, anchor_shas, path: "CHANGELOG.md")
        content = render(commits, anchor_shas)
        File.write(path, content)
        path
      end
    end
  end
end
