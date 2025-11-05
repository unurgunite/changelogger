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

      def generate(commits, anchor_shas, path: "CHANGELOG.md")
        sha_to_idx = commits.map(&:sha)
        anchor_indices = anchor_shas.map { |sha| sha_to_idx.index(sha) }.compact
        raise "Need at least 2 valid commits selected" if anchor_indices.size < 2

        versioned = Versioner.assign(commits, anchor_indices)

        header = "## [Unreleased]\n\n"
        sections = build_sections(versioned)
        content = [header, sections].join("\n")
        File.write(path, content)
        path
      end
    end
  end
end
