# frozen_string_literal: true

module Changelogger
  # +Changelogger::Versioner+ calculates version numbers for anchor and in-between commits.
  class Versioner
    class << self
      # +Changelogger::Versioner.distribute_patches+      -> Array<Integer>
      #
      # Evenly distributes patch numbers in the range 1..base across +k+ in-between commits.
      # Ensures strictly increasing sequence even when rounding collides.
      #
      # @param [Integer] k number of in-between items
      # @param [Integer] base upper bound for distribution (default: 10)
      # @return [Array<Integer>] strictly increasing patch numbers
      def distribute_patches(k, base: 10) # rubocop:disable Naming/MethodParameterName
        patches = []
        prev = 0
        1.upto(k) do |i|
          x = (i * base.to_f / (k + 1)).round
          x = prev + 1 if x <= prev
          patches << x
          prev = x
        end
        patches
      end

      # +Changelogger::Versioner.assign+                  -> Array<[Integer, Changelogger::Commit, String]>
      #
      # Assigns versions for anchor commits (minor increments) and patch versions for in-between commits.
      #
      # @param [Array<Changelogger::Commit>] commits all commits (chronological)
      # @param [Array<Integer>] anchor_indices indices into +commits+ marking anchors
      # @param [Integer] major major version (default: 0)
      # @param [Integer] minor_start starting minor number (default: 1)
      # @param [Integer] base_patch distribution base for patches (default: 10)
      # @return [Array<(Integer, Changelogger::Commit, String)>] each element is [index, commit, "x.y.z"]
      # @raise [ArgumentError] if fewer than 2 anchors are provided
      def assign(commits, anchor_indices, major: 0, minor_start: 1, base_patch: 10)
        raise ArgumentError, 'Need at least 2 anchors' if anchor_indices.size < 2

        anchor_indices = anchor_indices.sort.uniq
        version_map = {}

        anchor_indices.each_with_index do |idx, j|
          version_map[idx] = [major, minor_start + j, 0]
        end

        anchor_indices.each_with_index do |start_idx, j|
          break if j >= anchor_indices.size - 1

          end_idx = anchor_indices[j + 1]
          k = [end_idx - start_idx - 1, 0].max
          patches = distribute_patches(k, base: base_patch)

          (start_idx + 1).upto(end_idx - 1) do |i|
            pnum = patches[i - start_idx - 1]
            version_map[i] = [major, minor_start + j, pnum]
          end
        end

        version_map.keys.sort.map do |i|
          v = version_map[i]
          [i, commits[i], "#{v[0]}.#{v[1]}.#{v[2]}"]
        end
      end
    end
  end
end
