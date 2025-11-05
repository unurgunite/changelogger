# frozen_string_literal: true

module Changelogger
  class Versioner
    class << self
      # Distribute strictly increasing patch numbers between 1..base (default 10-ish)
      # Ensures monotonic sequence even when rounding collides.
      def distribute_patches(k, base: 10)
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

      # commits: array of Commit
      # anchor_indices: indices into commits (ascending order along history)
      # Returns array of [index, commit, "major.minor.patch"]
      def assign(commits, anchor_indices, major: 0, minor_start: 1, base_patch: 10)
        raise ArgumentError, "Need at least 2 anchors" if anchor_indices.size < 2

        anchor_indices = anchor_indices.sort.uniq
        version_map = {}

        # Set versions for anchors
        anchor_indices.each_with_index do |idx, j|
          version_map[idx] = [major, minor_start + j, 0]
        end

        # Fill between anchors with patch versions
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
